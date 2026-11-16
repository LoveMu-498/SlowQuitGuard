public enum HoldDuration {
    public static let tenthsRange = 5...30
    public static let range = 0.5...3.0
    public static let step = 0.1
    public static let defaultValue = 1.0
}

public enum HoldDurationRelation: Equatable, Sendable {
    case standard, shorter, longer

    init(duration: Double, globalDuration: Double?) {
        // The global slider and a stored integer number of tenths can reach
        // the same decimal value by different floating-point operations.
        guard let globalDuration, abs(duration - globalDuration) > 1e-9 else {
            self = .standard
            return
        }
        self = duration < globalDuration ? .shorter : .longer
    }
}
