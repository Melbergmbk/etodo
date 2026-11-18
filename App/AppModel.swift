import AppKit
import Observation
import MedyaCore

enum ToolsState: Equatable {
    case checking
    case preparing(Double)
    case ready
    case failed
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
    case done([URL])
}

struct ShownError: Equatable {
    var error: UserFacingError
    var details: String
}

@MainActor
@Observable
final class AppModel {
    static let browserKey = "browser"
    static let audioRates = [320, 192, 128]

    private(set) var toolsState: ToolsState = .checking
    private(set) var site: Site?
    var link = "" {
        didSet { if link != oldValue { linkChanged() } }
    }
    private(set) var preview: PreviewState = .empty
    var formatKind: FormatKind = .video { didSet { resetFinished() } }
    var videoHeight: Int? { didSet { resetFinished() } }
    var audioKbps = 320 { didSet { resetFinished() } }
    private(set) var destination: URL
    private(set) var recentFolders: [URL]
    private(set) var phase: DownloadPhase = .idle
    var error: ShownError?

    @ObservationIgnored private var tools: ToolManager?
    @ObservationIgnored private var downloader: Downloader?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.folderName, isDirectory: true)
        let saved = (defaults.stringArray(forKey: "recentFolders") ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
        recentFolders = saved.isEmpty ? [fallback] : saved
        destination = defaults.string(forKey: "destination").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? fallback
    }

    // MARK: Türetilmiş durum

    var isBusy: Bool {
        switch phase {
        case .starting, .downloading, .finishing: true
        default: false
        }
    }

    var canDownload: Bool {
        guard toolsState == .ready, !isBusy else { return false }
        switch preview {
        case .media, .gallery: return true
        default: return false
        }
    }

    var qualityOptions: [Int] {
        if case .media(let info) = preview { return info.availableHeights }
        return []
    }

    private var browser: Browser {
        Browser(rawValue: defaults.string(forKey: Self.browserKey) ?? "") ?? .chrome
    }

    // MARK: Araçlar

    func prepareTools() async {
        guard toolsState == .checking || toolsState == .failed else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.folderName, isDirectory: true)
        let runner = SystemProcessRunner()
        let manager = tools ?? ToolManager(root: support, fetcher: URLSessionFetcher(), runner: runner,
                                           arch: ToolManager.currentArch())
        tools = manager

        let missing = await manager.status().filter { !$0.isReady }.map(\.kind)
        if !missing.isEmpty {
            toolsState = .preparing(0)
            let (stream, continuation) = AsyncStream.makeStream(of: (ToolKind, Double).self)
            let order = missing
            let consumer = Task { @MainActor [weak self] in
                for await (kind, value) in stream {
                    guard let self, let index = order.firstIndex(of: kind) else { continue }
                    let overall = (Double(index) + value) / Double(order.count)
                    if case .preparing(let old) = self.toolsState, overall > old { self.toolsState = .preparing(overall) }
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
        downloader = Downloader(runner: runner, tools: await manager.paths)
        error = nil
        toolsState = .ready
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
        phase = .idle
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
                videoHeight = info.availableHeights.first
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

    // MARK: İndirme

    func startDownload() {
        guard canDownload, let downloader, let site, let url = Site.normalizedURL(link) else { return }
        let request = makeRequest(url, site, format: selectedFormat)
        error = nil
        phase = .starting
        downloadTask = Task { [weak self] in
            await self?.perform(request, with: downloader)
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func revealInFinder() {
        guard case .done(let files) = phase else { return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    private var selectedFormat: MediaFormat {
        if preview == .gallery { return .images }
        return formatKind == .audio ? .audio(kbps: audioKbps) : .video(maxHeight: videoHeight)
    }

    private func perform(_ request: DownloadRequest, with downloader: Downloader) async {
        let (stream, continuation) = AsyncStream.makeStream(of: DownloadProgress.self, bufferingPolicy: .bufferingNewest(8))
        let consumer = Task { @MainActor [weak self] in
            for await p in stream { self?.apply(p) }
        }
        do throws(UserFacingError) {
            let files = try await usingTools { () async throws(UserFacingError) -> [URL] in
                try await downloader.download(request) { continuation.yield($0) }
            }
            continuation.finish()
            await consumer.value
            phase = .done(files)
            remember(request.destination)
        } catch {
            continuation.finish()
            consumer.cancel()
            phase = .idle
            show(error, details: await downloader.lastErrorOutput)
        }
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

    // MARK: Kayıt yeri

    func choose(_ folder: URL) {
        guard !isBusy else { return }
        destination = folder
        defaults.set(folder.path, forKey: "destination")
        remember(folder)
        resetFinished()
    }

    func chooseOtherFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Seç"
        panel.message = "İndirilen dosyaların kaydedileceği klasörü seç."
        panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url { choose(url) }
    }

    private func remember(_ folder: URL) {
        recentFolders = Array(([folder] + recentFolders.filter { $0.standardizedFileURL != folder.standardizedFileURL }).prefix(3))
        defaults.set(recentFolders.map(\.path), forKey: "recentFolders")
    }

    // MARK: Yardımcılar

    private func makeRequest(_ url: URL, _ site: Site, format: MediaFormat) -> DownloadRequest {
        DownloadRequest(url: url, site: site, format: format, destination: destination, browser: browser)
    }

    private func resetFinished() {
        if case .done = phase { phase = .idle }
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
