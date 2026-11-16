import Foundation
import QuitGuardCore
import Testing
@testable import SlowQuitGuard

@MainActor
struct ApplicationHoldDurationTests {
    @Test func savedAppDurationsFollowListRulesAndReloadIndependently() throws {
        let domain = "SlowQuitGuard.Tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(1.1, forKey: "holdDuration")
        let model = ProtectionModel(defaults: defaults)
        let app = StoredApplication(bundleID: "test.duration.editor", name: "Editor", path: nil)
        let target = QuitTarget(identity: .init(processID: 99, bundleID: app.bundleID), name: app.name)

        #expect(model.makePolicy(for: target).duration == 1.1)
        model.saveDuration(6, for: app)
        #expect(model.protectedApplications.isEmpty)
        let policy = model.makePolicy(for: target)
        #expect(policy.duration == 0.6)
        #expect(policy.globalDuration == 1.1)

        model.saveDuration(25, for: .init(bundleID: "test.duration.other", name: "Other", path: nil))
        #expect(model.makePolicy(for: target) == policy)
        model.holdDuration = 1.5
        #expect(model.makePolicy(for: target) != policy)
        #expect(model.makePolicy(for: target).duration == 0.6)

        model.protectionMode = .whitelist
        #expect(model.makePolicy(for: target).unprotectedTarget == target)
        model.setProtection(false, for: app.bundleID)
        let reloaded = ProtectionModel(defaults: defaults)
        #expect(reloaded.makePolicy(for: target).target == nil)
        #expect(reloaded.customDuration(for: app.bundleID)?.tenths == 6)
        reloaded.setProtection(true, for: app.bundleID)
        #expect(reloaded.makePolicy(for: target).duration == 0.6)
        reloaded.saveDuration(nil, for: app)
        #expect(reloaded.makePolicy(for: target).duration == 1.5)
        #expect(ProtectionModel(defaults: defaults).customDuration(for: app.bundleID) == nil)
    }
}
