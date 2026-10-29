import Foundation

struct StoredApplication: Codable, Identifiable, Equatable {
    let bundleID: String
    let name: String
    let path: String?
    var id: String { bundleID }
}
