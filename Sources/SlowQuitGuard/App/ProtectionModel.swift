import AppKit
@preconcurrency import ApplicationServices
import Carbon.HIToolbox
import Observation
import QuitGuardCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class ProtectionModel {
    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "protectionEnabled")
            updatePolicy()
        }
    }
    var holdDuration: Double {
        didSet {
            UserDefaults.standard.set(holdDuration, forKey: "holdDuration")
            updatePolicy()
        }
    }
    private(set) var snapshot = ServiceSnapshot()
    private(set) var frontmostTarget: QuitTarget?
    private(set) var menuTarget: QuitTarget?
    private(set) var menuTargetIsPrevious = false
    private(set) var runningApplications: [RunningApplicationItem] = []
    let permissions = PermissionCoordinator.live()
    @ObservationIgnored let settingsWindow = SettingsWindowPresenter()
    var settingsTab: GuardSettingsTab = .general
    private var rules: ApplicationProtectionRules
    private var storedApplications: [String: StoredApplication]
    var applicationSelectionMessage: String?

    @ObservationIgnored private var service: EventTapService?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var layoutObserver: NSObjectProtocol?
    @ObservationIgnored private var qKeyCodes = KeyboardLayoutResolver.qKeyCodes()
    @ObservationIgnored private var awake = true
    @ObservationIgnored private var sessionActive = true
    @ObservationIgnored private let overlay = HoldOverlayController()
    @ObservationIgnored private var lastExternalTarget: QuitTarget?
    @ObservationIgnored private var menuObserver: NSObjectProtocol?
    @ObservationIgnored private var menuBeginObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: "protectionEnabled") as? Bool ?? true
        let storedDuration = defaults.double(forKey: "holdDuration")
        holdDuration = storedDuration.isFinite && (0.5...3).contains(storedDuration) ? storedDuration : 1
        let mode = ApplicationProtectionRules.Mode(rawValue: defaults.string(forKey: "protectionMode") ?? "") ?? .blacklist
        rules = ApplicationProtectionRules(mode: mode,
            protectedBundleIDs: Set(defaults.stringArray(forKey: "protectedBundleIDs") ?? []),
            excludedBundleIDs: Set(defaults.stringArray(forKey: "excludedBundleIDs") ?? []))
        let records = defaults.data(forKey: "applicationRecords").flatMap { try? JSONDecoder().decode([StoredApplication].self, from: $0) } ?? []
        storedApplications = Dictionary(records.map { ($0.bundleID, $0) }, uniquingKeysWith: { _, newer in newer })
    }

    var displayState: ProtectionState {
        if !enabled { return .paused }
        if snapshot.state == .ready && rules.mode == .whitelist && rules.protectedBundleIDs.isEmpty { return .selectionRequired }
        return snapshot.state
    }
    var permissionStage: PermissionStage { permissions.stage }
    var protectionMode: ApplicationProtectionRules.Mode {
        get { rules.mode }
        set { rules.setMode(newValue); saveRules() }
    }
    var protectedApplications: [StoredApplication] { records(for: rules.protectedBundleIDs) }
    var excludedApplications: [StoredApplication] { records(for: rules.excludedBundleIDs) }
    var currentAppExcluded: Bool {
        frontmostTarget.map { !rules.isProtected($0.identity.bundleID) } ?? false
    }
    var excludedBundleIDs: [String] { rules.excludedBundleIDs.sorted() }
    var durationLabel: String { holdDuration.formatted(.number.precision(.fractionLength(1))) + " 秒" }

    func start() {
        guard service == nil else { return }
        prepareMenu()
        let worker = EventTapService(policy: makePolicy()) { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, self.service != nil, value.revision > self.snapshot.revision else { return }
                self.snapshot = value
                if value.state == .connectionFailed(checkInputMonitoring: true) {
                    self.permissions.setInputMonitoringRequired(true)
                } else if value.state == .ready {
                    self.permissions.setInputMonitoringRequired(false)
                } else { self.permissions.refresh() }
                self.overlay.present(value.holdPresentation)
            }
        }
        service = worker
        permissions.onRefreshProtection = { [weak self] in self?.service?.reconnect() }
        menuObserver = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsWindow.menuDidClose() }
        }
        menuBeginObserver = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsWindow.menuDidBegin() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.didActivateApplicationNotification) { model in
            model.updateApplications()
            model.updatePolicy()
        }
        observe(center, NSWorkspace.didLaunchApplicationNotification) { $0.updateApplications(); $0.updatePolicy() }
        observe(center, NSWorkspace.didTerminateApplicationNotification) { $0.updateApplications(); $0.updatePolicy() }
        observe(center, NSWorkspace.willSleepNotification) { $0.awake = false; $0.updatePolicy() }
        observe(center, NSWorkspace.didWakeNotification) { $0.awake = true; $0.updatePolicy() }
        observe(center, NSWorkspace.screensDidSleepNotification) { $0.awake = false; $0.updatePolicy() }
        observe(center, NSWorkspace.screensDidWakeNotification) { $0.awake = true; $0.updatePolicy() }
        observe(center, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false; $0.updatePolicy() }
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification) {
            $0.sessionActive = true
            $0.updateApplications()
            $0.updatePolicy()
        }
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.qKeyCodes = KeyboardLayoutResolver.qKeyCodes()
                self.updatePolicy()
            }
        }
        worker.start()
    }

    func stop() {
        service?.stop()
        service = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        if let layoutObserver { DistributedNotificationCenter.default().removeObserver(layoutObserver) }
        layoutObserver = nil
        if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
        if let menuBeginObserver { NotificationCenter.default.removeObserver(menuBeginObserver) }
        menuObserver = nil
        menuBeginObserver = nil
        permissions.guideDidClose()
        permissions.onRefreshProtection = nil
        overlay.present(nil)
    }

    func repairProtection() {
        permissions.refresh(advance: false)
        service?.reconnect()
    }

    func prepareMenu() {
        updateApplications()
    }

    func isProtected(_ bundleID: String) -> Bool { rules.isProtected(bundleID) }

    func setProtection(_ enabled: Bool, for bundleID: String) {
        rules.setProtection(enabled, for: bundleID)
        if storedApplications[bundleID] == nil { storedApplications[bundleID] = ApplicationCatalog.record(for: bundleID) }
        saveRules()
    }

    func removeExclusion(_ id: String) { setProtection(true, for: id) }

    func restoreDefault(for id: String) { rules.restoreDefault(for: id); saveRules() }

    func excludedAppName(_ id: String) -> String {
        runningApplications.first(where: { $0.bundleID == id })?.name ?? ApplicationCatalog.name(for: id)
    }

    func checkPermissionsOnOpen() {
        permissions.showIfNeeded()
    }

    func requestAccessibility() {
        permissions.request(.accessibility)
    }

    func requestPostingPermission() {
        permissions.request(.eventPosting)
    }

    func requestInputMonitoring() {
        permissions.request(.inputMonitoring)
    }

    func chooseApplications(protected: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "添加"
        panel.message = protected ? "选择要加入“已保护应用”的 App" : "选择要加入“已排除应用”的 App"
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, response == .OK else { return }
                var added = false
                for url in panel.urls {
                    guard let record = ApplicationCatalog.record(for: url) else { continue }
                    self.storedApplications[record.bundleID] = record
                    self.rules.setProtection(protected, for: record.bundleID)
                    added = true
                }
                self.applicationSelectionMessage = added ? nil : "没有找到可添加的应用。请选择 App 文件。"
                self.saveRules()
            }
        }
    }

    private func records(for ids: Set<String>) -> [StoredApplication] {
        ids.map { id in
            if let current = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), let record = ApplicationCatalog.record(for: current) { return record }
            return storedApplications[id] ?? ApplicationCatalog.record(for: id)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func saveRules() {
        let defaults = UserDefaults.standard
        defaults.set(rules.mode.rawValue, forKey: "protectionMode")
        defaults.set(rules.protectedBundleIDs.sorted(), forKey: "protectedBundleIDs")
        defaults.set(rules.excludedBundleIDs.sorted(), forKey: "excludedBundleIDs")
        if let data = try? JSONEncoder().encode(Array(storedApplications.values)) { defaults.set(data, forKey: "applicationRecords") }
        updatePolicy()
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name,
        action: @escaping @MainActor (ProtectionModel) -> Void
    ) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        })
    }

    private func updateApplications() {
        frontmostTarget = CurrentApplication.target()
        if let frontmostTarget { lastExternalTarget = frontmostTarget }
        runningApplications = ApplicationCatalog.running()
        let previous = lastExternalTarget.flatMap { target in
            runningApplications.contains(where: { $0.bundleID == target.identity.bundleID }) ? target : nil
        }
        menuTarget = frontmostTarget ?? previous
        menuTargetIsPrevious = frontmostTarget == nil && previous != nil
    }

    private func makePolicy() -> RuntimePolicy {
        let protectedTarget = currentAppExcluded ? nil : frontmostTarget
        return RuntimePolicy(enabled: enabled, duration: holdDuration,
                             sessionActive: awake && sessionActive,
                             target: protectedTarget, qKeyCodes: qKeyCodes)
    }

    private func updatePolicy() { service?.updatePolicy(makePolicy()) }
}
