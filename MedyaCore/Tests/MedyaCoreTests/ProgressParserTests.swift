import Testing
@testable import MedyaCore

@Suite struct ProgressParserTests {
    @Test func totalBytes() {
        #expect(ProgressParser.parse(line: "MI|500|1000|NA|2048.5|3")
                == DownloadProgress(fraction: 0.5, bytesPerSecond: 2048.5, eta: 3))
    }

    @Test func fallsBackToEstimate() {
        #expect(ProgressParser.parse(line: "MI|500|NA|2000|NA|NA")
                == DownloadProgress(fraction: 0.25, bytesPerSecond: nil, eta: nil))
    }

    @Test func noTotalAtAll() {
        #expect(ProgressParser.parse(line: "MI|500|NA|NA|100|NA")
                == DownloadProgress(fraction: nil, bytesPerSecond: 100, eta: nil))
    }

    @Test func clampsAndTrims() {
        #expect(ProgressParser.parse(line: "MI|1200|1000|NA|NA|NA\r\n")?.fraction == 1.0)
    }

    @Test func ignoresOtherLines() {
        #expect(ProgressParser.parse(line: "[info] foo") == nil)
        #expect(ProgressParser.parse(line: "") == nil)
        #expect(ProgressParser.parse(line: "MI|bozuk") == nil)
    }
}
