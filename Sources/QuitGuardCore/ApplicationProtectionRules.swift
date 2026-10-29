public struct ApplicationProtectionRules: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case blacklist
        case whitelist
    }

    public private(set) var mode: Mode
    public private(set) var protectedBundleIDs: Set<String>
    public private(set) var excludedBundleIDs: Set<String>

    public init(mode: Mode = .blacklist, protectedBundleIDs: Set<String> = [], excludedBundleIDs: Set<String> = []) {
        self.mode = mode
        self.protectedBundleIDs = protectedBundleIDs.subtracting(excludedBundleIDs)
        self.excludedBundleIDs = excludedBundleIDs
    }

    public func isProtected(_ bundleID: String) -> Bool {
        if excludedBundleIDs.contains(bundleID) { return false }
        if protectedBundleIDs.contains(bundleID) { return true }
        return mode == .blacklist
    }

    public mutating func setProtection(_ enabled: Bool, for bundleID: String) {
        if enabled {
            excludedBundleIDs.remove(bundleID)
            protectedBundleIDs.insert(bundleID)
        } else {
            protectedBundleIDs.remove(bundleID)
            excludedBundleIDs.insert(bundleID)
        }
    }

    public mutating func setMode(_ value: Mode) { mode = value }

    public mutating func restoreDefault(for bundleID: String) {
        protectedBundleIDs.remove(bundleID)
        excludedBundleIDs.remove(bundleID)
    }
}
