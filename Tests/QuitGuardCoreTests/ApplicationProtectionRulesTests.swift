import Testing
@testable import QuitGuardCore

@Test func exclusionLeavesOtherApplicationsProtected() {
    var rules = ApplicationProtectionRules()
    rules.setProtection(false, for: "com.google.Chrome")
    #expect(!rules.isProtected("com.google.Chrome"))
    #expect(rules.isProtected("com.apple.TextEdit"))
}

@Test func multipleSelectionsPersistIndependently() {
    var rules = ApplicationProtectionRules(excludedBundleIDs: ["first", "second"])
    rules.setProtection(true, for: "first")
    rules.setProtection(false, for: "third")
    #expect(rules.isProtected("first"))
    #expect(!rules.isProtected("second"))
    #expect(!rules.isProtected("third"))
    #expect(ApplicationProtectionRules(mode: rules.mode, protectedBundleIDs: rules.protectedBundleIDs, excludedBundleIDs: rules.excludedBundleIDs) == rules)
}

@Test func legacyExclusionsKeepBlacklistBehavior() {
    let rules = ApplicationProtectionRules(excludedBundleIDs: ["browser"])
    #expect(rules.mode == .blacklist)
    #expect(!rules.isProtected("browser"))
    #expect(rules.isProtected("new-application"))
}

@Test func whitelistOnlyProtectsExplicitSelections() {
    var rules = ApplicationProtectionRules(mode: .whitelist)
    #expect(!rules.isProtected("new-application"))
    rules.setProtection(true, for: "editor")
    #expect(rules.isProtected("editor"))
    #expect(!rules.isProtected("browser"))
}

@Test func movingBetweenColumnsCannotLeaveConflictingRules() {
    var rules = ApplicationProtectionRules()
    rules.setProtection(true, for: "editor")
    rules.setProtection(false, for: "editor")
    #expect(!rules.protectedBundleIDs.contains("editor"))
    #expect(rules.excludedBundleIDs.contains("editor"))
    rules.setProtection(true, for: "editor")
    #expect(rules.protectedBundleIDs.contains("editor"))
    #expect(!rules.excludedBundleIDs.contains("editor"))
}

@Test func switchingModeKeepsBothListsAndChangesOnlyUnlistedApplications() {
    var rules = ApplicationProtectionRules(protectedBundleIDs: ["editor"], excludedBundleIDs: ["browser"])
    #expect(rules.isProtected("unlisted"))
    rules.setMode(.whitelist)
    #expect(rules.isProtected("editor"))
    #expect(!rules.isProtected("browser"))
    #expect(!rules.isProtected("unlisted"))
    rules.setMode(.blacklist)
    #expect(rules.isProtected("unlisted"))
}

@Test func restoringDefaultFollowsTheSelectedMode() {
    var rules = ApplicationProtectionRules(excludedBundleIDs: ["browser"])
    rules.restoreDefault(for: "browser")
    #expect(rules.isProtected("browser"))
    rules.setMode(.whitelist)
    rules.setProtection(true, for: "browser")
    rules.restoreDefault(for: "browser")
    #expect(!rules.isProtected("browser"))
}
