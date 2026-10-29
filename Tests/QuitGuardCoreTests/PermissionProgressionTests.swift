import Testing
@testable import QuitGuardCore

@Test func permissionStatusKeepsGrantsSeparateFromWhetherTheyAreRequired() {
    let access = PermissionAccess(accessibility: true, eventPosting: false, inputMonitoring: false)
    #expect(access.isGranted(.accessibility))
    #expect(!access.isGranted(.eventPosting))
    #expect(!access.isGranted(.inputMonitoring))
    #expect(access.isRequired(.accessibility))
    #expect(access.isRequired(.eventPosting))
    #expect(!access.isRequired(.inputMonitoring))
    #expect(access.nextRequirement == .eventPosting)
}

@Test func authorizationMovesThroughRequiredPermissionsWithoutRepeatedPrompts() {
    var flow = PermissionProgression()
    var access = PermissionAccess(accessibility: false, eventPosting: false, inputMonitoring: false)
    #expect(flow.automaticRequest(for: access) == .accessibility)
    #expect(flow.automaticRequest(for: access) == nil)
    access.accessibility = true
    #expect(flow.automaticRequest(for: access) == .eventPosting)
    #expect(flow.automaticRequest(for: access) == nil)
    access.eventPosting = true
    #expect(access.nextRequirement == nil)
    #expect(flow.automaticRequest(for: access) == nil)
}

@Test func oneSystemGrantMayCompleteSeveralChecks() {
    var flow = PermissionProgression()
    #expect(flow.automaticRequest(for: .init(accessibility: false, eventPosting: false, inputMonitoring: false)) == .accessibility)
    let access = PermissionAccess(accessibility: true, eventPosting: true, inputMonitoring: false)
    #expect(access.nextRequirement == nil)
    #expect(flow.automaticRequest(for: access) == nil)
}

@Test func inputMonitoringIsRequestedOnlyWhenTheRuntimeNeedsIt() {
    var flow = PermissionProgression()
    var access = PermissionAccess(accessibility: true, eventPosting: true, inputMonitoring: false)
    #expect(access.nextRequirement == nil)
    access.inputMonitoringRequired = true
    #expect(flow.automaticRequest(for: access) == .inputMonitoring)
    access.inputMonitoring = true
    #expect(access.nextRequirement == nil)
}
