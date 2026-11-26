import AppKit
import ApplicationServices

/// Reads notification banners while they are on screen, through the Accessibility API.
/// Notification text is only kept in memory; the log gets timings and element roles.
struct Banner {
    var texts: [String]
    var app: SourceApp?
    /// The native banner, so a click on the island can do what a click on the banner does.
    var element: AXUIElement
    /// Alerts stay until answered and carry buttons (calls, reminders), so they are never hidden.
    var isAlert: Bool
}

final class BannerWatcher {
    var onBanner: ((Banner) -> Void)?

    /// Moves the native banner off screen after reading it. Nothing is closed or deleted.
    var hidesNativeBanner = true {
        didSet { if !hidesNativeBanner { restoreWindows() } }
    }
    /// More banners than this is probably the Notification Center list, which must stay put.
    private let maxBannersToHide = 3
    private let offScreen = CGPoint(x: 30000, y: 30000)
    private var moved: [(window: AXUIElement, origin: CGPoint)] = []
    private var lastMoveResult = ""

    private var visible: [String: Int] = [:]
    private var hasBaseline = false
    private var lastDiagnostic = ""
    private var lastAttributeNames = ""
    private let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]

    func poll() {
        guard let process = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return }
        let app = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)

        var windowsValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)
        guard error == .success, let windows = windowsValue as? [AXUIElement] else { return }

        var banners: [Banner] = []
        var bannerWindows: [AXUIElement] = []
        for window in windows {
            let before = banners.count
            findBanners(window, depth: 0, into: &banners)
            let found = banners[before...]
            if !found.isEmpty && !found.contains(where: { $0.isAlert }) { bannerWindows.append(window) }
        }

        if banners.contains(where: { $0.isAlert }) {
            // An alert needs its own buttons: bring everything back into view.
            restoreWindows()
        } else if hidesNativeBanner && !bannerWindows.isEmpty && banners.count <= maxBannersToHide {
            bannerWindows.forEach(moveAway)
        } else {
            restoreWindows()
        }

        if banners.isEmpty && !windows.isEmpty { logStructure(windows) }

        var now: [String: Int] = [:]
        for banner in banners {
            let key = banner.texts.joined(separator: "\u{1}")
            now[key, default: 0] += 1
            if hasBaseline && now[key]! > visible[key, default: 0] {
                Log.write("banner captured, \(banner.texts.count) text field(s), app: \(banner.app?.name ?? "not identified")")
                onBanner?(banner)
            }
        }
        visible = now
        hasBaseline = true
    }

    /// Same as clicking the native banner. False once macOS has removed it.
    func press(_ element: AXUIElement) -> Bool {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        Log.write("island clicked, pressing native banner: error \(error.rawValue)")
        return error == .success
    }

    private func moveAway(_ window: AXUIElement) {
        guard let current = position(of: window) else { return }
        // Already out of sight.
        if moved.contains(where: { CFEqual($0.window, window) }) && current.x > 10000 { return }

        let error = setPosition(offScreen, of: window)
        let after = position(of: window) ?? current
        if after != current && !moved.contains(where: { CFEqual($0.window, window) }) {
            moved.append((window, current))
        }
        let result = "move native banner: error \(error.rawValue), from \(Int(current.x)),\(Int(current.y))"
            + " to \(Int(after.x)),\(Int(after.y))"
        if result != lastMoveResult {
            lastMoveResult = result
            Log.write(result)
        }
    }

    func restoreWindows() {
        for entry in moved { _ = setPosition(entry.origin, of: entry.window) }
        moved.removeAll()
    }

    private func position(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    private func setPosition(_ point: CGPoint, of window: AXUIElement) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private func findBanners(_ element: AXUIElement, depth: Int, into result: inout [Banner]) {
        if depth > 10 { return }
        if bannerSubroles.contains(string(element, kAXSubroleAttribute)) {
            var texts: [String] = []
            collectTexts(element, depth: 0, into: &texts)
            if !texts.isEmpty {
                let app = SourceApp.find(in: descriptions(of: element))
                if app == nil { logAttributeNames(element) }
                result.append(Banner(texts: texts, app: app, element: element,
                                     isAlert: string(element, kAXSubroleAttribute) == "AXNotificationCenterAlert"))
            }
            return
        }
        for child in children(element) { findBanners(child, depth: depth + 1, into: &result) }
    }

    /// The banner's spoken description starts with the app name.
    private func descriptions(of element: AXUIElement) -> [String] {
        var found = [string(element, kAXDescriptionAttribute)]
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXAttributedDescription" as CFString, &value)
        if let attributed = value as? NSAttributedString { found.append(attributed.string) }
        found.append(string(element, kAXTitleAttribute))
        return found.filter { !$0.isEmpty }
    }

    /// Attribute names only, never their values.
    private func logAttributeNames(_ element: AXUIElement) {
        var names: CFArray?
        AXUIElementCopyAttributeNames(element, &names)
        let line = "banner attributes: " + ((names as? [String]) ?? []).joined(separator: " ")
        if line != lastAttributeNames {
            lastAttributeNames = line
            Log.write(line)
        }
    }

    private func collectTexts(_ element: AXUIElement, depth: Int, into texts: inout [String]) {
        if depth > 6 { return }
        if string(element, kAXRoleAttribute) == kAXStaticTextRole {
            let value = string(element, kAXValueAttribute)
            if !value.isEmpty { texts.append(value) }
        }
        for child in children(element) { collectTexts(child, depth: depth + 1, into: &texts) }
    }

    /// If macOS names the banner elements differently, this shows what it uses (roles only, no text).
    private func logStructure(_ windows: [AXUIElement]) {
        var lines: [String] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            if depth > 8 || lines.count > 60 { return }
            lines.append(String(repeating: "  ", count: depth)
                + string(element, kAXRoleAttribute) + " " + string(element, kAXSubroleAttribute))
            for child in children(element) { walk(child, depth + 1) }
        }
        for window in windows { walk(window, 0) }
        let diagnostic = lines.joined(separator: "\n")
        if diagnostic != lastDiagnostic {
            lastDiagnostic = diagnostic
            Log.write("no banner element recognised; structure:\n" + diagnostic)
        }
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value as? String ?? ""
    }
}

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NotchProto.log")

    static func write(_ message: String) {
        let line = String(format: "%.3f ", Date().timeIntervalSince1970) + message + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
