import Foundation

public protocol HTTPFetching: Sendable {
    func data(from: URL) async throws -> Data
    func download(from: URL, to: URL, progress: @escaping @Sendable (Double) -> Void) async throws
    /// Yönlendirmeler izlendikten sonraki asıl adres (gövde indirilmez).
    func finalURL(of: URL) async throws -> URL
}

public enum FetchError: Error, Equatable, Sendable {
    case badStatus(Int)
}

public final class URLSessionFetcher: HTTPFetching {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(AppIdentity.folderName, forHTTPHeaderField: "User-Agent")
        if url.host == "api.github.com" { r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        return r
    }

    private func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.badStatus(http.statusCode)
        }
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: request(url))
        try check(response)
        return data
    }

    public func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let (tmp, response) = try await session.download(for: request(url), delegate: ProgressDelegate(progress))
        try check(response)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
    }

    public func finalURL(of url: URL) async throws -> URL {
        let (bytes, response) = try await session.bytes(for: request(url))
        bytes.task.cancel()
        try check(response)
        return response.url ?? url
    }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    init(_ onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
