import AppKit
import QuitGuardCore

struct RunningApplicationItem: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    var id: String { bundleID }
}

@MainActor
enum ApplicationCatalog {
    static func running() -> [RunningApplicationItem] {
        var result: [String: RunningApplicationItem] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, !app.isTerminated,
                  let id = app.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier, id != "com.apple.finder" else { continue }
            result[id] = RunningApplicationItem(bundleID: id, name: app.localizedName ?? id, icon: app.icon)
        }
        return result.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return url.deletingPathExtension().lastPathComponent
    }

    static func record(for url: URL) -> StoredApplication? {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier, id != "com.apple.finder", id != Bundle.main.bundleIdentifier else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return StoredApplication(bundleID: id, name: name, path: url.path)
    }

    static func record(for bundleID: String) -> StoredApplication {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), let record = record(for: url) {
            return record
        }
        return StoredApplication(bundleID: bundleID, name: name(for: bundleID), path: nil)
    }
}
