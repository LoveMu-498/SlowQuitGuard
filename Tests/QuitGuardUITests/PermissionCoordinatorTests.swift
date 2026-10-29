import QuitGuardCore
import Testing
@testable import SlowQuitGuard

@Suite(.serialized)
@MainActor
struct PermissionCoordinatorTests {
    @Test func eachSettingsButtonKeepsItsOwnTargetEvenWhenAnotherPermissionIsMissing() {
        let access = PermissionAccess(accessibility: false, eventPosting: false, inputMonitoring: false)
        var requests: [PermissionRequirement] = []
        var destinations: [PermissionRequirement] = []
        let coordinator = PermissionCoordinator(readAccess: { access }, requestAccess: { requests.append($0) },
            openSettings: { destinations.append($0) })
        coordinator.openSettings(for: .inputMonitoring)
        coordinator.openSettings(for: .eventPosting)
        coordinator.openSettings(for: .accessibility)
        #expect(destinations == [.inputMonitoring, .eventPosting, .accessibility])
        #expect(requests == destinations)
        #expect(!coordinator.access.inputMonitoringRequired)
        #expect(coordinator.stage == .accessibility)
    }

    @Test func grantedPermissionsCanStillOpenTheirOwnSettingsWithoutRequestingAgain() {
        let access = PermissionAccess(accessibility: true, eventPosting: true, inputMonitoring: true)
        var requests: [PermissionRequirement] = []
        var destinations: [PermissionRequirement] = []
        let coordinator = PermissionCoordinator(readAccess: { access }, requestAccess: { requests.append($0) },
            openSettings: { destinations.append($0) })
        for permission in PermissionRequirement.allCases { coordinator.openSettings(for: permission) }
        #expect(destinations == PermissionRequirement.allCases)
        #expect(requests.isEmpty)
        #expect(coordinator.stage == .ready)
    }

    @Test func theVisibleGuideDetectsPermissionChangesWithoutAButtonPress() async throws {
        var access = PermissionAccess(accessibility: false, eventPosting: false, inputMonitoring: false)
        var requests: [PermissionRequirement] = []
        let coordinator = PermissionCoordinator(readAccess: { access }, requestAccess: { requests.append($0) }, openSettings: { _ in })
        defer { coordinator.guideDidClose() }
        coordinator.showIfNeeded()
        access.accessibility = true
        for _ in 0..<100 {
            if coordinator.stage == .posting { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(coordinator.stage == .posting)
        #expect(requests == [.accessibility, .eventPosting])
    }

    @Test func grantingOnePermissionAutomaticallyRequestsTheNext() {
        var access = PermissionAccess(accessibility: false, eventPosting: false, inputMonitoring: false)
        var requests: [PermissionRequirement] = []
        let coordinator = PermissionCoordinator(readAccess: { access }, requestAccess: { requests.append($0) }, openSettings: { _ in })
        defer { coordinator.guideDidClose() }
        coordinator.showIfNeeded()
        #expect(requests == [.accessibility])
        access.accessibility = true
        coordinator.refresh()
        #expect(coordinator.stage == .posting)
        #expect(requests == [.accessibility, .eventPosting])
        coordinator.refresh()
        #expect(requests.count == 2)
        access.eventPosting = true
        coordinator.refresh()
        #expect(coordinator.stage == .ready)
    }

    @Test func explicitContinueChecksFreshStateAndCannotSkipMissingAccess() {
        var access = PermissionAccess(accessibility: false, eventPosting: false, inputMonitoring: false)
        let coordinator = PermissionCoordinator(readAccess: { access }, requestAccess: { _ in }, openSettings: { _ in })
        defer { coordinator.guideDidClose() }
        coordinator.showIfNeeded()
        coordinator.checkAndContinue()
        #expect(coordinator.stage == .accessibility)
        #expect(coordinator.lastCheckStillMissing)
        access.accessibility = true
        access.eventPosting = true
        coordinator.checkAndContinue()
        #expect(coordinator.stage == .ready)
        #expect(!coordinator.lastCheckStillMissing)
    }

    @Test func closingTheGuideStopsAutomaticRequestsUntilItIsReopened() {
        var access = PermissionAccess(accessibility: false, eventPosting: false, inputMonitoring: false)
        var requests: [PermissionRequirement] = []
        let coordinator = PermissionCoordinator(readAccess: { access }, requestAccess: { requests.append($0) }, openSettings: { _ in })
        coordinator.showIfNeeded()
        coordinator.guideDidClose()
        access.accessibility = true
        coordinator.refresh()
        #expect(requests == [.accessibility])
        coordinator.showIfNeeded()
        #expect(requests == [.accessibility, .eventPosting])
        coordinator.guideDidClose()
    }
}
