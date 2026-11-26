import AppKit
import Combine
import SwiftUI

/// Lets the playback buttons work on the first click, without activating the app.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class IslandPanel: NSPanel {
    // Without this macOS pushes the window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = IslandModel()
    private let watcher = BannerWatcher()
    private let nowPlaying = NowPlaying()
    private var trackUntil = Date.distantPast
    private var lastIdentity: String?
    private var hasCheckedTrack = false
    private let trackSeconds: TimeInterval = 4
    private var panel: IslandPanel!
    private let spring = SpringAnimator()
    private var expansion: AnyCancellable?
    private var statusItem: NSStatusItem!
    private var showUntil = Date.distantPast
    private var tick = 0

    private let notificationSeconds: TimeInterval = 6
    /// While more are waiting, each notification gets this long.
    private let queuedSeconds: TimeInterval = 2.5
    private var queue: [(note: Note, banner: Banner)] = []
    private var currentBanner: Banner?
    private var shownAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let i = arguments.firstIndex(of: "--resolve") {
            SourceApp.report(Array(arguments.dropFirst(i + 1)))
            exit(0)
        }
        if let i = arguments.firstIndex(of: "--snapshot"), arguments.count > i + 1 {
            Snapshot.render(to: URL(fileURLWithPath: arguments[i + 1]))
            exit(0)
        }

        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // Clicks go to whatever is underneath, except while the mouse is on the open island.
        panel.ignoresMouseEvents = true
        let glass = GlassContainer(content: ClickThroughHostingView(rootView: IslandView(model: model)))
        panel.contentView = glass
        spring.onChange = { [weak self, weak glass] openness in
            glass?.apply(size: Layout.size(at: openness), radius: Layout.radius(at: openness))
            self?.model.openness = openness
        }
        expansion = model.$expanded.removeDuplicates().sink { [weak self] open in
            self?.spring.move(to: open ? 1 : 0)
        }
        model.send = { [weak self] command in
            self?.nowPlaying.send(command)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.refreshTrack() }
        }
        position()
        panel.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.make()
        statusItem.button?.toolTip = "Kentongan"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Keluar dari Kentongan",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let hideItem = NSMenuItem(title: "Sembunyikan banner bawaan",
                                  action: #selector(toggleNativeBanner(_:)), keyEquivalent: "")
        hideItem.target = self
        hideItem.state = .on
        menu.insertItem(hideItem, at: 0)
        statusItem.menu = menu

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.position() }

        // Asks macOS to show its permission prompt the first time.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        model.trusted = AXIsProcessTrustedWithOptions(options)
        Log.write("started, accessibility permission: \(model.trusted)")

        watcher.onBanner = { [weak self] banner in
            guard let self else { return }
            var note = Note(texts: banner.texts)
            note.app = banner.app
            self.queue.append((note, banner))
            // Keep the newest if a flood arrives.
            if self.queue.count > 20 { self.queue.removeFirst() }
            self.model.waiting = self.queue.count
            self.advanceQueue()
        }
        model.openNote = { [weak self] in self?.openCurrentNote() }

        SourceApp.buildIndex()

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceQueue() {
        guard !queue.isEmpty else { return }
        let now = Date()
        if now < showUntil && now.timeIntervalSince(shownAt) < queuedSeconds { return }
        let next = queue.removeFirst()
        currentBanner = next.banner
        shownAt = now
        showUntil = now.addingTimeInterval(notificationSeconds)
        model.note = next.note
        model.waiting = queue.count
        model.showingNote = true
        model.expanded = true
    }

    /// Opens what the notification points to; if the banner is already gone, just opens the app.
    private func openCurrentNote() {
        guard let banner = currentBanner else { return }
        if !watcher.press(banner.element), let app = banner.app {
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        }
        currentBanner = nil
        showUntil = .distantPast
        model.note = nil
    }

    private func refreshTrack() {
        nowPlaying.fetch { [weak self] track in
            guard let self else { return }
            // Open briefly when a different song starts, not for the one already playing at launch.
            if let track, track.isPlaying, track.identity != self.lastIdentity {
                if self.hasCheckedTrack { self.trackUntil = Date().addingTimeInterval(self.trackSeconds) }
                self.lastIdentity = track.identity
            }
            self.hasCheckedTrack = true
            if track != self.model.track { self.model.track = track }
        }
    }

    @objc private func toggleNativeBanner(_ item: NSMenuItem) {
        watcher.hidesNativeBanner.toggle()
        item.state = watcher.hidesNativeBanner ? .on : .off
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.restoreWindows()
    }

    private var screen: NSScreen { NSScreen.screens[0] }

    private func position() {
        let frame = screen.frame
        panel.setFrame(NSRect(x: frame.midX - Layout.window.width / 2,
                              y: frame.maxY - Layout.window.height,
                              width: Layout.window.width, height: Layout.window.height), display: true)
    }

    private func update() {
        tick += 1
        if tick % 10 == 0 {
            let trusted = AXIsProcessTrusted()
            if trusted != model.trusted {
                model.trusted = trusted
                Log.write("accessibility permission: \(trusted)")
            }
        }
        // Every 0.2 s while allowed to read banners.
        if model.trusted && tick % 2 == 0 && !spring.isAnimating { watcher.poll() }

        let size = model.expanded ? Layout.expanded : Layout.collapsed
        let frame = screen.frame
        let hoverArea = NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                               width: size.width, height: size.height + 2)
        if tick % 5 == 0 { refreshTrack() }

        let hovering = hoverArea.contains(NSEvent.mouseLocation)
        // A notification being read does not disappear under the mouse.
        if hovering && Date() < showUntil && queue.isEmpty {
            showUntil = max(showUntil, Date().addingTimeInterval(1.5))
        }
        if !hovering { advanceQueue() }
        let showingNote = Date() < showUntil
        if showingNote != model.showingNote { model.showingNote = showingNote }
        let shouldExpand = hovering || showingNote || Date() < trackUntil
        if shouldExpand != model.expanded { model.expanded = shouldExpand }
        let ignoresMouse = !(hovering && model.expanded)
        if ignoresMouse != panel.ignoresMouseEvents { panel.ignoresMouseEvents = ignoresMouse }
    }
}

/// Draws the island states to PNG files so the layout can be checked without running the app.
enum Snapshot {
    @MainActor static func render(to folder: URL) {
        let long = Note(texts: ["Budi Santoso", "Grup Proyek",
                                "Besok meeting jam sepuluh ya, tolong siapkan laporan mingguan dan daftar bug yang masih terbuka"])
        var short = Note(texts: ["Claude Code", "Claude selesai ngerjain"])
        short.app = SourceApp.named("Script Editor")
        let states: [(String, Bool, Bool, Note?)] = [
            ("collapsed", false, true, nil), ("short", true, true, short), ("long", true, true, long),
            ("empty", true, true, nil), ("permission", true, false, nil),
        ]
        // Uses an app that exists on every Mac, to check the source label and icon.
        let sample = NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app")
        let song = Track(title: "Lilakne Lungamu", artist: "Jeyma Monica", isPlaying: true,
                         duration: 371, elapsed: 97, measuredAt: Date(), artwork: nil,
                         appName: "Google Chrome", appIcon: sample)
        for (name, expanded, music) in [("player", true, song), ("collapsed-music", false, song)] {
            let model = IslandModel()
            model.expanded = expanded
            model.openness = expanded ? 1 : 0
            model.track = music
            save(model, name, to: folder)
        }
        for (name, expanded, trusted, note) in states {
            let model = IslandModel()
            model.expanded = expanded
            model.openness = expanded ? 1 : 0
            model.trusted = trusted
            model.note = note
            model.showingNote = note != nil
            save(model, name, to: folder)
        }
    }

    @MainActor private static func save(_ model: IslandModel, _ name: String, to folder: URL) {
            let renderer = ImageRenderer(content: IslandView(model: model).background(
                LinearGradient(colors: [Color(red: 0.32, green: 0.22, blue: 0.45), Color(red: 0.16, green: 0.36, blue: 0.42)],
                               startPoint: .leading, endPoint: .trailing)))
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
            try? data.write(to: folder.appendingPathComponent("\(name).png"))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
