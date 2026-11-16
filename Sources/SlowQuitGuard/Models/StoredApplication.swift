import Foundation

struct StoredApplication: Codable, Identifiable, Equatable {
    let bundleID: String
    let name: String
    let path: String?
    var id: String { bundleID }
}

struct ApplicationHoldDuration: Codable, Identifiable, Equatable {
    let application: StoredApplication
    let tenths: Int

    var id: String { application.bundleID }
    var duration: Double { Double(tenths) / 10 }
}
