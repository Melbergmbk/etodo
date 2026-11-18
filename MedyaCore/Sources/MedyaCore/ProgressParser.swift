import Foundation

public struct DownloadProgress: Sendable, Equatable {
    public var fraction: Double?
    public var bytesPerSecond: Double?
    public var eta: TimeInterval?

    public init(fraction: Double?, bytesPerSecond: Double?, eta: TimeInterval?) {
        self.fraction = fraction
        self.bytesPerSecond = bytesPerSecond
        self.eta = eta
    }
}

public enum ProgressParser {
    /// Biçim: `MI|indirilen|toplam|tahmini_toplam|hız|kalan_süre`
    public static func parse(line: String) -> DownloadProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("MI|") else { return nil }
        let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 6 else { return nil }
        func number(_ s: String) -> Double? {
            s == "NA" ? nil : Double(s)
        }
        var fraction: Double?
        if let done = number(parts[1]), let total = number(parts[2]) ?? number(parts[3]), total > 0 {
            fraction = min(max(done / total, 0), 1)
        }
        return DownloadProgress(fraction: fraction, bytesPerSecond: number(parts[4]), eta: number(parts[5]))
    }
}
