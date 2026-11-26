import AppKit

/// The app a notification came from, used for its name, its icon and to open it.
struct SourceApp: Equatable {
    var name: String
    var url: URL
    var icon: NSImage

    private static var cache: [String: SourceApp] = [:]
    private static var index: [String: URL] = [:]
    private static var indexedAt = Date.distantPast
    private static let folders = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications",
                                  "/System/Library/CoreServices", "/System/Library/CoreServices/Applications"]

    /// Takes the part before the first comma of each description and matches it to an app.
    static func find(in descriptions: [String]) -> SourceApp? {
        for description in descriptions {
            let first = description.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
            if let app = named(first) { return app }
        }
        return nil
    }

    static func named(_ rawName: String) -> SourceApp? {
        let name = clean(rawName)
        guard !name.isEmpty, name.count < 60 else { return nil }
        let key = name.lowercased()
        if let known = cache[key] { return known }

        // Running apps first, then everything installed.
        var url = NSWorkspace.shared.runningApplications
            .first { clean($0.localizedName ?? "").lowercased() == key && $0.bundleURL?.pathExtension == "app" }?
            .bundleURL
        if url == nil {
            // Rebuild now and then so newly installed apps are found, without rescanning for every unknown name.
            if index[key] == nil && Date().timeIntervalSince(indexedAt) > 60 { buildIndex() }
            // Some system apps (Safari) do not show up when a folder is listed, but their path works.
            url = index[key] ?? folders.map { URL(fileURLWithPath: "\($0)/\(name).app") }
                .first { !name.contains("/") && FileManager.default.fileExists(atPath: $0.path) }
        }
        guard let url else { return nil }
        let app = SourceApp(name: name, url: url, icon: NSWorkspace.shared.icon(forFile: url.path))
        cache[key] = app
        return app
    }

    /// Some names carry invisible direction marks (WhatsApp does).
    private static func clean(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.properties.generalCategory != .format }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every .app in the application folders, up to two folders deep, under each of its names.
    static func buildIndex() {
        index = [:]
        indexedAt = Date()
        for folder in folders { scan(URL(fileURLWithPath: folder), depth: 0) }
    }

    private static func scan(_ folder: URL, depth: Int) {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for item in items {
            if item.pathExtension == "app" {
                let bundle = Bundle(url: item)
                let names: [String?] = [
                    item.deletingPathExtension().lastPathComponent,
                    FileManager.default.displayName(atPath: item.path).replacingOccurrences(of: ".app", with: ""),
                    bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
                    bundle?.infoDictionary?["CFBundleDisplayName"] as? String,
                    bundle?.infoDictionary?["CFBundleName"] as? String,
                ]
                for name in names.compactMap({ $0 }) {
                    let key = clean(name).lowercased()
                    if !key.isEmpty && index[key] == nil { index[key] = item }
                }
            } else if depth < 2,
                      (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                scan(item, depth: depth + 1)
            }
        }
    }

    /// Prints which of these names are recognised (used to check detection without sending notifications).
    static func report(_ names: [String]) {
        buildIndex()
        print("indexed names: \(index.count)")
        for name in names {
            print("\(name) -> \(named(name)?.url.path ?? "NOT FOUND")")
        }
    }
}
