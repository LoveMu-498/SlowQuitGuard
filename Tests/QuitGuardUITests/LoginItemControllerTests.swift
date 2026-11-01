import Foundation
import ServiceManagement
import Testing
@testable import SlowQuitGuard

@Suite(.serialized)
@MainActor
struct LoginItemControllerTests {
    @Test func openingSettingsNeverRegistersTheApp() {
        var changes = 0
        let controller = LoginItemController(readStatus: { .notRegistered },
            register: { changes += 1 }, unregister: { changes += 1 }, openSettings: {})
        controller.refresh()
        #expect(!controller.isEnabled)
        #expect(changes == 0)
    }

    @Test func enablingAndDisablingFollowTheSystemAndRepeatedRequestsAreHarmless() async {
        var systemStatus: SMAppService.Status = .notRegistered
        var registrations = 0
        var removals = 0
        let controller = LoginItemController(readStatus: { systemStatus },
            register: { registrations += 1; systemStatus = .enabled },
            unregister: { removals += 1; systemStatus = .notRegistered }, openSettings: {})
        await controller.setEnabled(true)
        await controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(registrations == 1)
        await controller.setEnabled(false)
        await controller.setEnabled(false)
        #expect(!controller.isEnabled)
        #expect(removals == 1)
        #expect(controller.errorMessage == nil)
    }

    @Test func aSuccessfulCallAloneDoesNotClaimThatAutoLaunchIsEnabled() async {
        let controller = LoginItemController(readStatus: { .notRegistered },
            register: {}, unregister: {}, openSettings: {})
        await controller.setEnabled(true)
        #expect(!controller.isEnabled)
        #expect(controller.errorMessage != nil)
    }

    @Test func pendingApprovalStaysOffAndCanBeRemovedWithoutGrantingPermission() async {
        var systemStatus: SMAppService.Status = .notRegistered
        var registrations = 0
        var settingsOpened = 0
        let controller = LoginItemController(readStatus: { systemStatus },
            register: { registrations += 1; systemStatus = .requiresApproval },
            unregister: { systemStatus = .notRegistered }, openSettings: { settingsOpened += 1 })
        await controller.setEnabled(true)
        #expect(controller.status == .requiresApproval)
        #expect(!controller.isEnabled)
        #expect(controller.errorMessage == nil)
        await controller.setEnabled(true)
        #expect(settingsOpened == 1)
        #expect(registrations == 1)
        await controller.setEnabled(false)
        #expect(controller.status == .notRegistered)
    }

    @Test func systemChangesAreReadWithoutReenablingAnItemTheUserDisabled() {
        var systemStatus: SMAppService.Status = .enabled
        var mutations = 0
        let controller = LoginItemController(readStatus: { systemStatus },
            register: { mutations += 1 }, unregister: { mutations += 1 }, openSettings: {})
        #expect(controller.isEnabled)
        systemStatus = .requiresApproval
        controller.refresh()
        #expect(!controller.isEnabled)
        systemStatus = .enabled
        controller.refresh()
        #expect(controller.isEnabled)
        systemStatus = .notRegistered
        controller.refresh()
        #expect(!controller.isEnabled)
        #expect(mutations == 0)
    }

    @Test func registrationFailureKeepsTheToggleOffAndCanBeRetried() async {
        var shouldFail = true
        var systemStatus: SMAppService.Status = .notRegistered
        let controller = LoginItemController(readStatus: { systemStatus }, register: {
            if shouldFail { throw TestFailure() }
            systemStatus = .enabled
        }, unregister: {}, openSettings: {})
        await controller.setEnabled(true)
        #expect(!controller.isEnabled)
        #expect(controller.errorMessage?.contains("测试服务暂不可用") == true)
        #expect(!controller.isChanging)
        shouldFail = false
        await controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(controller.errorMessage == nil)
    }

    @Test func removalFailureKeepsTheToggleOn() async {
        let controller = LoginItemController(readStatus: { .enabled },
            register: {}, unregister: { throw TestFailure() }, openSettings: {})
        await controller.setEnabled(false)
        #expect(controller.isEnabled)
        #expect(controller.errorMessage?.hasPrefix("未能关闭自动启动") == true)
        #expect(!controller.isChanging)
    }

    @Test func incompleteRemovalDoesNotClaimThatTheItemWasRemoved() async {
        let controller = LoginItemController(readStatus: { .enabled },
            register: {}, unregister: {}, openSettings: {})
        await controller.setEnabled(false)
        #expect(controller.isEnabled)
        #expect(controller.errorMessage != nil)
    }

    @Test func anUnregisteredMainAppCanReportNotFoundAndStillRegister() async {
        var systemStatus: SMAppService.Status = .notFound
        let controller = LoginItemController(readStatus: { systemStatus },
            register: { systemStatus = .enabled }, unregister: {}, openSettings: {})
        #expect(!controller.isEnabled)
        await controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(controller.errorMessage == nil)
    }

    @Test func notFoundWhileDisablingIsAlreadyOff() async {
        var removals = 0
        let controller = LoginItemController(readStatus: { .notFound },
            register: {}, unregister: { removals += 1; throw TestFailure() }, openSettings: {})
        await controller.setEnabled(false)
        #expect(!controller.isEnabled)
        #expect(removals == 0)
        #expect(controller.errorMessage == nil)
    }

    @Test func registrationMustCreateAnEligibleLoginItem() async {
        let controller = LoginItemController(readStatus: { .notFound },
            register: {}, unregister: {}, openSettings: {})
        await controller.setEnabled(true)
        #expect(!controller.isEnabled)
        #expect(controller.errorMessage?.contains("重新打开") == true)
    }

    @Test func aConcurrentCompletedRequestIsNotReportedAsAFailure() async {
        var systemStatus: SMAppService.Status = .notRegistered
        let controller = LoginItemController(readStatus: { systemStatus }, register: {
            systemStatus = .enabled
            throw TestFailure()
        }, unregister: {}, openSettings: {})
        await controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(controller.errorMessage == nil)
    }

    @Test func changesAreIgnoredWhileTheRemovalIsInFlight() async throws {
        var systemStatus: SMAppService.Status = .enabled
        var finishRemoval: CheckedContinuation<Void, Never>?
        var registrations = 0
        let controller = LoginItemController(readStatus: { systemStatus },
            register: { registrations += 1; systemStatus = .enabled }, unregister: {
                await withCheckedContinuation { finishRemoval = $0 }
                systemStatus = .notRegistered
            }, openSettings: {})
        let removal = Task { await controller.setEnabled(false) }
        for _ in 0..<100 where finishRemoval == nil { await Task.yield() }
        let continuation = try #require(finishRemoval)
        #expect(controller.isChanging)
        await controller.setEnabled(true)
        #expect(registrations == 0)
        continuation.resume()
        await removal.value
        #expect(!controller.isChanging)
        #expect(!controller.isEnabled)
    }

    @Test func systemSettingsCanBeOpenedWithoutChangingRegistration() {
        var settingsOpened = 0
        var mutations = 0
        let controller = LoginItemController(readStatus: { .notRegistered },
            register: { mutations += 1 }, unregister: { mutations += 1 },
            openSettings: { settingsOpened += 1 })
        controller.openLoginItems()
        #expect(settingsOpened == 1)
        #expect(mutations == 0)
    }

    private struct TestFailure: LocalizedError {
        var errorDescription: String? { "测试服务暂不可用" }
    }
}
