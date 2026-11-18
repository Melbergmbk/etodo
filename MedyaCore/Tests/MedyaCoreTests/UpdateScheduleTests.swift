import Testing
import Foundation
@testable import MedyaCore

@Suite struct UpdateScheduleTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

    @Test func fortySevenHoursIsNotDue() {
        #expect(UpdateSchedule.shouldCheck(lastCheck: ago(47), now: now) == false)
        #expect(UpdateSchedule.badge(appUpdateAvailable: false, lastSuccessfulCheck: ago(47), now: now) == .hidden)
    }

    @Test func fortyNineHoursIsOverdue() {
        #expect(UpdateSchedule.shouldCheck(lastCheck: ago(49), now: now) == true)
        #expect(UpdateSchedule.badge(appUpdateAvailable: false, lastSuccessfulCheck: ago(49), now: now) == .checkOverdue)
    }

    @Test func appUpdateWinsAlways() {
        #expect(UpdateSchedule.badge(appUpdateAvailable: true, lastSuccessfulCheck: ago(1), now: now) == .updateAvailable)
        #expect(UpdateSchedule.badge(appUpdateAvailable: true, lastSuccessfulCheck: ago(100), now: now) == .updateAvailable)
        #expect(UpdateSchedule.badge(appUpdateAvailable: true, lastSuccessfulCheck: nil, now: now) == .updateAvailable)
    }

    @Test func neverCheckedMeansCheckNow() {
        #expect(UpdateSchedule.shouldCheck(lastCheck: nil, now: now) == true)
    }
}
