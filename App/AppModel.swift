import AppKit
import Observation
import MedyaCore

enum ToolsState: Equatable {
    case checking
    /// İlk kurulum (ya da eksik araç) — `SetupView`.
    case preparing
    case ready
    case failed
}

/// Ayarlar › Araçlar'da süren iş.
enum ToolAction: Equatable {
    case updating
    case rollingBack(ToolKind)
}

enum PreviewState: Equatable {
    case empty
    case loading
    case media(MediaInfo)
    case gallery
}

enum FormatKind: Hashable {
    case video, audio
}

enum DownloadPhase: Equatable {
    case idle
    /// İlk ilerleme bilgisi gelmeden önce (gallery-dl hiç ilerleme vermez).
    case starting
    case downloading(fraction: Double, bytesPerSecond: Double?, eta: TimeInterval?)
    /// İkinci akış (ses), birleştirme ya da MP3 dönüştürme: yüzde gerileyip kafa karıştırmasın diye belirsiz gösterilir.
    case finishing
}

/// İndirmeler listesindeki bekleyen, süren ya da olmayan iş. Bitenler `DownloadRecord` olarak geçmişe geçer.
struct QueueItem: Identifiable, Equatable {
    enum State: Equatable {
        case queued, running
        case failed(ShownError)
    }
    let id = UUID()
    var title: String
    var detail: String
    var link: String
    var request: DownloadRequest
    var state: State

    static func == (a: QueueItem, b: QueueItem) -> Bool {
        a.id == b.id && a.state == b.state && a.title == b.title
    }
}

struct ShownError: Equatable {
    var error: UserFacingError
    var details: String
}

@MainActor
@Observable
final class AppModel {
    static let browserKey = "browser"
    static let disclaimerKey = "disclaimerAccepted"
    static let keychainExplainedKey = "keychainExplained"

    /// Doluyken Anahtar Zinciri açıklaması gösterilir; kullanıcı cevap verince devam eder.
    var keychainPrompt: Browser?
    @ObservationIgnored private var keychainAnswer: CheckedContinuation<Bool, Never>?
    static let audioRates = [320, 192, 128]
    static let formatKey = "lastFormat"
    static let heightKey = "lastVideoHeight"
    static let audioKey = "lastAudioKbps"
    static let subtitlesKey = "subtitles"
    static let historyKey = "downloadHistory"

    private(set) var disclaimerAccepted: Bool
    private(set) var toolsState: ToolsState = .checking
    /// Kurulumda sırayla kurulan araçlar ve her birinin ilerlemesi (0…1).
    private(set) var setupKinds: [ToolKind] = []
    private(set) var setupProgress: [ToolKind: Double] = [:]
    /// Kendiliğinden kaybolan kısa bildirim.
    private(set) var toast: String?
    var browser: Browser {
        didSet { defaults.set(browser.rawValue, forKey: Self.browserKey) }
    }

    // Ayarlar › Araçlar
    private(set) var toolStatuses: [ToolStatus] = []
    private(set) var activity: [ActivityEntry] = []
    private(set) var lastToolCheck: Date?
    private(set) var toolAction: ToolAction?
    var toolsError: ShownError?
    private(set) var site: Site?
    var link = "" {
        didSet { if link != oldValue { linkChanged() } }
    }
    private(set) var preview: PreviewState = .empty
    /// Biçim ve kalite seçimleri hatırlanır; haftada bir MP3 indiren her seferinde yeniden seçmesin.
    var formatKind: FormatKind = .video {
        didSet { defaults.set(formatKind == .audio ? "audio" : "video", forKey: Self.formatKey) }
    }
    var videoHeight: Int? {
        didSet {
            if !applyingPreferredHeight, let videoHeight { defaults.set(videoHeight, forKey: Self.heightKey) }
        }
    }
    var subtitles = false {
        didSet { defaults.set(subtitles, forKey: Self.subtitlesKey) }
    }
    var audioKbps = 192 {
        didSet { defaults.set(audioKbps, forKey: Self.audioKey) }
    }
    private(set) var destination: URL
    private(set) var recentFolders: [URL]
    /// Süren indirmenin ilerlemesi (listede o satırda gösterilir).
    private(set) var phase: DownloadPhase = .idle
    private(set) var queue: [QueueItem] = []
    private(set) var history: [DownloadRecord]
    var error: ShownError?

    @ObservationIgnored private var tools: ToolManager?
    @ObservationIgnored private var downloader: Downloader?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var periodicUpdates: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var applyingPreferredHeight = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Kayıt yeri, Etodo klasörünün duracağı üst klasördür (varsayılan ~/Downloads → ~/Downloads/Etodo/…).
        let fallback = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        // Eski adla (Medya İndirici) seçilmiş kayıt yeri yeni bundle id'nin ayarlarına bir kez taşınır.
        let old = defaults.string(forKey: "destination") == nil ? UserDefaults(suiteName: Self.legacyBundleID) : nil
        let storedRecent = defaults.stringArray(forKey: "recentFolders") ?? old?.stringArray(forKey: "recentFolders") ?? []
        var seen = Set<String>()
        let saved = storedRecent.map { FolderLayout.parentFolder(stored: $0, fallback: fallback) }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
        recentFolders = saved.isEmpty ? [fallback] : Array(saved.prefix(3))
        destination = FolderLayout.parentFolder(stored: defaults.string(forKey: "destination") ?? old?.string(forKey: "destination"),
                                                fallback: fallback)
        disclaimerAccepted = defaults.bool(forKey: Self.disclaimerKey)
        history = DownloadHistory.decode(defaults.data(forKey: Self.historyKey))
        formatKind = defaults.string(forKey: Self.formatKey) == "audio" ? .audio : .video
        subtitles = defaults.bool(forKey: Self.subtitlesKey)
        let savedKbps = defaults.integer(forKey: Self.audioKey)
        audioKbps = Self.audioRates.contains(savedKbps) ? savedKbps : 192
        browser = Browser(rawValue: defaults.string(forKey: Self.browserKey) ?? "") ?? Self.systemDefaultBrowser()
        defaults.set(destination.path, forKey: "destination")
        defaults.set(recentFolders.map(\.path), forKey: "recentFolders")
    }

    /// Sistemin varsayılan tarayıcısı desteklenenlerdense o, değilse Chrome.
    private static let legacyBundleID = "app.medyaindirici.mac"

    static func systemDefaultBrowser() -> Browser {
        guard let https = URL(string: "https://example.com"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: https),
              let id = Bundle(url: app)?.bundleIdentifier?.lowercased() else { return .chrome }
        let known: [String: Browser] = ["com.google.chrome": .chrome, "com.apple.safari": .safari,
                                        "com.brave.browser": .brave, "org.mozilla.firefox": .firefox,
                                        "com.microsoft.edgemac": .edge]
        return known[id] ?? .chrome
    }

    func acceptDisclaimer() {
        defaults.set(true, forKey: Self.disclaimerKey)
        disclaimerAccepted = true
    }

    // MARK: Türetilmiş durum

    /// Süren ya da sırada bekleyen indirme var mı (çıkışta uyarı için).
    var isBusy: Bool {
        queue.contains { $0.state == .queued || $0.state == .running }
    }

    var isDownloading: Bool { queue.contains { $0.state == .running } }

    var canDownload: Bool {
        guard toolsState == .ready else { return false }
        switch preview {
        case .media, .gallery: return true
        default: return false
        }
    }

    /// Instagram gönderileri (/p/) gallery-dl ile orijinal kalitede iner; kalite seçimi işlemez.
    var qualityIsOriginal: Bool {
        guard site == .instagram, formatKind == .video,
              let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.pathComponents.dropFirst().first?.lowercased() == "p"
    }

    /// Altyazı seçeneği yalnız YouTube videolarında gösterilir.
    var offersSubtitles: Bool {
        guard site == .youtube, formatKind == .video, case .media = preview else { return false }
        return true
    }

    var qualityOptions: [Int] {
        if case .media(let info) = preview { return info.availableHeights }
        return []
    }

    // MARK: Araçlar

    static let supportFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(AppIdentity.folderName, isDirectory: true)

    @ObservationIgnored private let runner = SystemProcessRunner()

    private func manager() -> ToolManager {
        if let tools { return tools }
        let m = ToolManager(root: Self.supportFolder, fetcher: URLSessionFetcher(), runner: runner,
                            arch: ToolManager.currentArch())
        tools = m
        return m
    }

    /// Eksik araç varsa kurar (`SetupView`), sonra ana pencereye geçer; kurulum olmadıysa arka planda güncelleme denetler.
    func prepareTools() async {
        guard disclaimerAccepted, toolsState == .checking || toolsState == .failed else { return }
        let manager = manager()
        await manager.removeLeftovers()

        let missing = await manager.status().filter { !$0.isReady }.map(\.kind)
        if !missing.isEmpty {
            setupKinds = missing
            setupProgress = [:]
            error = nil
            toolsState = .preparing
            let (stream, continuation) = AsyncStream.makeStream(of: (ToolKind, Double).self)
            let consumer = Task { @MainActor [weak self] in
                for await (kind, value) in stream {
                    guard let self else { continue }
                    if value > self.setupProgress[kind, default: 0] { self.setupProgress[kind] = value }
                }
            }
            do throws(UserFacingError) {
                try await manager.installMissing { continuation.yield(($0, $1)) }
                continuation.finish()
                await consumer.value
            } catch {
                continuation.finish()
                consumer.cancel()
                toolsState = .failed
                show(error, details: "")
                return
            }
        }
        downloader = Downloader(runner: runner, tools: await manager.paths,
                                beforeCookies: { [weak self] browser in await self?.allowCookies(browser) ?? false })
        error = nil
        toolsState = .ready
        await refreshToolInfo()
        // Açılışta yalnız 2 günde bir bakılır; bir site bozulursa indirme hatası zaten güncellemeyi tetikler.
        if missing.isEmpty, UpdateSchedule.shouldCheck(lastCheck: lastToolCheck, now: Date()) {
            Task { await self.updateTools(announce: true) }
        }
        // Uygulama günlerce açık kalırsa araçlar yine 2 günde bir güncellenir.
        periodicUpdates?.cancel()
        periodicUpdates = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(UpdateSchedule.interval))
                guard !Task.isCancelled else { return }
                await self?.updateTools(announce: true)
            }
        }
    }

    /// Ayarlar › Araçlar için durum, kayıt ve son kontrol.
    func refreshToolInfo() async {
        let manager = manager()
        toolStatuses = await manager.status()
        activity = await manager.log.entries()
        lastToolCheck = await manager.lastCheck()
    }

    func updateToolsNow() {
        guard toolAction == nil else { return }
        Task { await updateTools(announce: false) }
    }

    private func updateTools(announce: Bool) async {
        guard toolAction == nil else { return }
        toolAction = .updating
        toolsError = nil
        let updated = await manager().updateAll()
        toolAction = nil
        await refreshToolInfo()
        if announce, !updated.isEmpty { showToast("İndirme araçları güncellendi") }
    }

    func rollback(_ kind: ToolKind) {
        guard toolAction == nil else { return }
        toolAction = .rollingBack(kind)
        toolsError = nil
        Task {
            do throws(UserFacingError) {
                try await manager().rollback(kind)
            } catch {
                toolsError = ShownError(error: error, details: "")
            }
            toolAction = nil
            await refreshToolInfo()
        }
    }

    func revealToolsFolder() {
        let folder = Self.supportFolder.appendingPathComponent("tools", isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: folder.path) ? folder : Self.supportFolder])
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Sekme ve link

    func select(_ newSite: Site) {
        guard newSite != site, !isBusy else { return }
        site = newSite
        link = ""
    }

    private func linkChanged() {
        fetchTask?.cancel()
        error = nil
        guard let url = Site.normalizedURL(link), let detected = Site.detect(link) else {
            preview = .empty
            return
        }
        if site != detected { site = detected }
        preview = .loading
        fetchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.fetch(url, detected)
        }
    }

    private func fetch(_ url: URL, _ site: Site) async {
        guard let downloader else { return }
        let request = makeRequest(url, site, format: .video(maxHeight: nil))
        do throws(UserFacingError) {
            let result = try await usingTools { () async throws(UserFacingError) -> FetchResult in
                try await downloader.fetchInfo(request)
            }
            guard !Task.isCancelled else { return }
            switch result {
            case .media(let info):
                let preferred = defaults.object(forKey: Self.heightKey) as? Int
                applyingPreferredHeight = true
                videoHeight = info.height(closestTo: preferred)
                applyingPreferredHeight = false
                preview = .media(info)
            case .images:
                preview = .gallery
            }
        } catch {
            guard !Task.isCancelled else { return }
            preview = .empty
            show(error, details: await downloader.lastErrorOutput)
        }
    }

    // MARK: İndirme ve sıra

    /// Seçili linki sıraya ekler ve formu boşaltır; yenisi hemen yapıştırılabilir.
    func startDownload() {
        guard canDownload, let site, let url = Site.normalizedURL(link) else { return }
        var request = makeRequest(url, site, format: selectedFormat)
        request.subtitles = subtitles && offersSubtitles
        let title: String
        if case .media(let info) = preview, !info.title.isEmpty { title = info.title } else { title = url.host() ?? link }
        queue.append(QueueItem(title: title, detail: Self.detail(for: request.format, original: qualityIsOriginal),
                               link: url.absoluteString, request: request, state: .queued))
        error = nil
        DoneNotifier.requestPermission()
        link = ""
        startNext()
    }

    func cancel(_ id: QueueItem.ID) {
        guard let item = queue.first(where: { $0.id == id }) else { return }
        if item.state == .running {
            downloadTask?.cancel()
        } else {
            queue.removeAll { $0.id == id }
        }
    }

    func retry(_ id: QueueItem.ID) {
        guard let i = queue.firstIndex(where: { $0.id == id }) else { return }
        if case .failed(let shown) = queue[i].state, error == shown { error = nil }
        queue[i].state = .queued
        startNext()
    }

    func showError(_ id: QueueItem.ID) {
        if case .failed(let shown)? = queue.first(where: { $0.id == id })?.state { error = shown }
    }

    /// Geçmişteki bir indirmeyi aynı biçimle yeniden sıraya ekler (tarayıcı ve kayıt yeri bugünkü ayarlardan).
    func downloadAgain(_ record: DownloadRecord) {
        guard toolsState == .ready, let url = URL(string: record.link) else { return }
        var request = makeRequest(url, record.site, format: record.format)
        request.subtitles = record.subtitles
        queue.append(QueueItem(title: record.title, detail: record.detail, link: record.link, request: request, state: .queued))
        startNext()
    }

    func reveal(_ record: DownloadRecord) {
        let existing = record.files.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.isEmpty {
            showToast("Dosya taşınmış ya da silinmiş.")
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(existing)
        }
    }

    /// Bitenleri ve olmayanları listeden kaldırır; dosyalara dokunmaz.
    func clearFinished() {
        queue.removeAll { if case .failed = $0.state { true } else { false } }
        history = []
        defaults.removeObject(forKey: Self.historyKey)
    }

    var hasFinished: Bool {
        !history.isEmpty || queue.contains { if case .failed = $0.state { true } else { false } }
    }

    private func startNext() {
        guard !isDownloading, let downloader, let i = queue.firstIndex(where: { $0.state == .queued }) else { return }
        queue[i].state = .running
        phase = .starting
        let item = queue[i]
        downloadTask = Task { [weak self] in
            await self?.perform(item, with: downloader)
        }
    }

    private var selectedFormat: MediaFormat {
        if preview == .gallery { return .images }
        return formatKind == .audio ? .audio(kbps: audioKbps) : .video(maxHeight: videoHeight)
    }

    static func detail(for format: MediaFormat, original: Bool) -> String {
        switch format {
        case .images: "Fotoğraflar"
        case .audio(let kbps): "MP3 · \(kbps) kbps"
        case .video(let h): original ? "Orijinal kalite" : h.map { FormatPicker.label(for: $0) } ?? "En iyi kalite"
        }
    }

    private func perform(_ item: QueueItem, with downloader: Downloader) async {
        let (stream, continuation) = AsyncStream.makeStream(of: DownloadProgress.self, bufferingPolicy: .bufferingNewest(8))
        let consumer = Task { @MainActor [weak self] in
            for await p in stream { self?.apply(p) }
        }
        do throws(UserFacingError) {
            let files = try await usingTools { () async throws(UserFacingError) -> [URL] in
                try await downloader.download(item.request) { continuation.yield($0) }
            }
            continuation.finish()
            await consumer.value
            queue.removeAll { $0.id == item.id }
            history = DownloadHistory.adding(
                DownloadRecord(title: item.title, detail: item.detail, link: item.link, site: item.request.site,
                               format: item.request.format, subtitles: item.request.subtitles, files: files.map(\.path)),
                to: history)
            defaults.set(DownloadHistory.encode(history), forKey: Self.historyKey)
            DoneNotifier.notify(files)
            remember(item.request.destination)
            await logDownload(files)
        } catch {
            continuation.finish()
            consumer.cancel()
            if error == .cancelled {
                queue.removeAll { $0.id == item.id }
            } else {
                let shown = ShownError(error: error, details: await downloader.lastErrorOutput)
                if let i = queue.firstIndex(where: { $0.id == item.id }) { queue[i].state = .failed(shown) }
                show(error, details: shown.details)
            }
        }
        phase = .idle
        startNext()
    }

    private func apply(_ p: DownloadProgress) {
        switch phase {
        case .starting:
            guard let f = p.fraction else { return }
            phase = f >= 0.999 ? .finishing : .downloading(fraction: f, bytesPerSecond: p.bytesPerSecond, eta: p.eta)
        case .downloading(let previous, let speed, let eta):
            guard let f = p.fraction else {
                phase = .downloading(fraction: previous, bytesPerSecond: p.bytesPerSecond ?? speed, eta: p.eta ?? eta)
                return
            }
            // Akış bitti ya da yeni akış (ses) sıfırdan başladı
            if f >= 0.999 || f + 0.05 < previous {
                phase = .finishing
            } else {
                phase = .downloading(fraction: max(previous, f), bytesPerSecond: p.bytesPerSecond, eta: p.eta)
            }
        default:
            break
        }
    }

    /// Araç takası ile çakışmamak için her çalıştırma `beginDownload`/`endDownload` arasında;
    /// araç uyumsuz görünürse önce güncellenir, sonra bir kez daha denenir.
    private func usingTools<T: Sendable>(_ operation: () async throws(UserFacingError) -> T) async throws(UserFacingError) -> T {
        guard let tools else { throw .needsToolUpdate }
        do throws(UserFacingError) {
            return try await guarded(tools, operation)
        } catch where error == .needsToolUpdate && !Task.isCancelled {
            _ = await tools.updateAll()
            return try await guarded(tools, operation)
        }
    }

    private func guarded<T: Sendable>(_ tools: ToolManager,
                                      _ operation: () async throws(UserFacingError) -> T) async throws(UserFacingError) -> T {
        await tools.beginDownload()
        do throws(UserFacingError) {
            let value = try await operation()
            await tools.endDownload()
            return value
        } catch {
            await tools.endDownload()
            throw error
        }
    }

    /// Yalnız dosya adı yazılır; link ya da tam yol kaydedilmez.
    private func logDownload(_ files: [URL]) async {
        guard let tools, let first = files.first else { return }
        let text = files.count == 1
            ? "İndirildi: \(first.lastPathComponent)"
            : "İndirildi: \(files.count) dosya (\(first.deletingLastPathComponent().lastPathComponent))"
        await tools.log.append(text)
        activity = await tools.log.entries()
    }

    // MARK: Çerez izni

    /// Chromium tarayıcılarda macOS'un parola penceresinden önce bir kez ne olacağını anlatır.
    func allowCookies(_ browser: Browser) async -> Bool {
        guard browser.usesKeychain, !defaults.bool(forKey: Self.keychainExplainedKey) else { return true }
        return await withCheckedContinuation { cont in
            keychainAnswer?.resume(returning: false)
            keychainAnswer = cont
            keychainPrompt = browser
        }
    }

    func answerKeychainPrompt(_ proceed: Bool) {
        if proceed { defaults.set(true, forKey: Self.keychainExplainedKey) }
        keychainPrompt = nil
        keychainAnswer?.resume(returning: proceed)
        keychainAnswer = nil
    }

    // MARK: Kayıt yeri

    func choose(_ picked: URL) {
        // Etodo klasörünün kendisi seçildiyse iç içe Etodo/Etodo oluşmasın
        let folder = FolderLayout.parentFolder(stored: picked.path, fallback: destination)
        destination = folder
        defaults.set(folder.path, forKey: "destination")
        remember(folder)
    }

    func chooseOtherFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Seç"
        panel.message = "\(AppIdentity.folderName) klasörünün oluşturulacağı yeri seç."
        panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url { choose(url) }
    }

    private func remember(_ folder: URL) {
        recentFolders = Array(([folder] + recentFolders.filter { $0.standardizedFileURL != folder.standardizedFileURL }).prefix(3))
        defaults.set(recentFolders.map(\.path), forKey: "recentFolders")
    }

    // MARK: Sorun bildirimi

    /// Hata metninin başına eklenen sürüm bilgileri; kişisel veri (link, dosya adı) içermez.
    var diagnostics: String {
        let info = Bundle.main.infoDictionary
        let app = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let tools = toolStatuses.map { "\($0.kind.displayName) \($0.installedVersion ?? "yok")" }.joined(separator: ", ")
        return """
        Etodo \(app) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(Self.chipName())
        Tarayıcı: \(browser.displayName)
        Araçlar: \(tools.isEmpty ? "bilinmiyor" : tools)
        """
    }

    private static func chipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let name = String(cString: buffer)
        return name.isEmpty ? "bilinmeyen işlemci" : name
    }

    // MARK: Yardımcılar

    private func makeRequest(_ url: URL, _ site: Site, format: MediaFormat) -> DownloadRequest {
        DownloadRequest(url: url, site: site, format: format, destination: destination, browser: browser)
    }

    private func show(_ error: UserFacingError, details: String) {
        guard error != .cancelled else { return }
        self.error = ShownError(error: error, details: details)
    }

    func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        link = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: Önizleme durumları

extension AppModel {
    static func preview(site: Site? = nil, link: String = "", preview: PreviewState = .empty,
                        phase: DownloadPhase = .idle, error: ShownError? = nil,
                        tools: ToolsState = .ready) -> AppModel {
        let model = AppModel(defaults: UserDefaults(suiteName: "preview") ?? .standard)
        model.disclaimerAccepted = true
        model.toolsState = tools
        model.site = site
        model.link = link
        model.fetchTask?.cancel()
        model.preview = preview
        if case .media(let info) = preview { model.videoHeight = info.availableHeights.first }
        model.phase = phase
        model.error = error
        return model
    }

    static let sampleInfo = MediaInfo(title: "Big Buck Bunny — 4K Sürüm", uploader: "Blender Foundation",
                                      duration: 634, thumbnailURL: nil, availableHeights: [2160, 1440, 1080, 720, 480])
}
