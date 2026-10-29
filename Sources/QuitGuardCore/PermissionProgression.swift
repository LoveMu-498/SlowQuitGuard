public enum PermissionRequirement: String, CaseIterable, Hashable, Sendable {
    case accessibility
    case eventPosting
    case inputMonitoring
}

public struct PermissionAccess: Equatable, Sendable {
    public var accessibility: Bool
    public var eventPosting: Bool
    public var inputMonitoring: Bool
    public var inputMonitoringRequired: Bool

    public init(accessibility: Bool, eventPosting: Bool, inputMonitoring: Bool, inputMonitoringRequired: Bool = false) {
        self.accessibility = accessibility
        self.eventPosting = eventPosting
        self.inputMonitoring = inputMonitoring
        self.inputMonitoringRequired = inputMonitoringRequired
    }

    public var nextRequirement: PermissionRequirement? {
        if !accessibility { return .accessibility }
        if !eventPosting { return .eventPosting }
        if inputMonitoringRequired && !inputMonitoring { return .inputMonitoring }
        return nil
    }

    public func isGranted(_ requirement: PermissionRequirement) -> Bool {
        switch requirement {
        case .accessibility: accessibility
        case .eventPosting: eventPosting
        case .inputMonitoring: inputMonitoring
        }
    }

    public func isRequired(_ requirement: PermissionRequirement) -> Bool {
        requirement != .inputMonitoring || inputMonitoringRequired
    }
}

public struct PermissionProgression: Sendable {
    private var requested: Set<PermissionRequirement> = []

    public init() {}

    public mutating func automaticRequest(for access: PermissionAccess) -> PermissionRequirement? {
        guard let next = access.nextRequirement, requested.insert(next).inserted else { return nil }
        return next
    }

    public mutating func recordRequest(_ requirement: PermissionRequirement) { requested.insert(requirement) }
}
