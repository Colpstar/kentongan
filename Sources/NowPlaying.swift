import AppKit

struct Track: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var duration: Double
    var elapsed: Double
    /// When `elapsed` was measured.
    var measuredAt: Date
    var artwork: NSImage?
    /// The app macOS says is playing, e.g. "Google Chrome" (not the website inside it).
    var appName = ""
    var appIcon: NSImage?

    var identity: String { title + "\u{1}" + artist }

    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let position = elapsed + (isPlaying ? date.timeIntervalSince(measuredAt) : 0)
        return min(max(position / duration, 0), 1)
    }
}

/// The system "Now Playing" info, from the private MediaRemote framework.
/// Apple stopped answering third-party apps in macOS 15.4; this works on macOS 13.
final class NowPlaying {
    enum Command: Int32 {
        case togglePlayPause = 2
        case next = 4
        case previous = 5
    }

    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool

    private typealias GetPID = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void

    private let getInfo: GetInfo?
    private let getPID: GetPID?
    private var sourcePID: Int32 = 0
    private var sourceName = ""
    private var sourceIcon: NSImage?
    private let sendCommand: SendCommand?
    private var artworkData: Data?
    private var artworkImage: NSImage?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        getInfo = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo").map { unsafeBitCast($0, to: GetInfo.self) }
        getPID = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID").map { unsafeBitCast($0, to: GetPID.self) }
        sendCommand = dlsym(handle, "MRMediaRemoteSendCommand").map { unsafeBitCast($0, to: SendCommand.self) }
    }

    /// Calls back on the main queue with nil when nothing has a title.
    func fetch(_ completion: @escaping (Track?) -> Void) {
        guard let getPID else {
            fetchInfo(completion)
            return
        }
        getPID(.main) { [weak self] pid in
            guard let self else { return }
            if pid != self.sourcePID {
                self.sourcePID = pid
                let app = NSRunningApplication(processIdentifier: pid)
                self.sourceName = app?.localizedName ?? ""
                self.sourceIcon = app?.icon
            }
            self.fetchInfo(completion)
        }
    }

    private func fetchInfo(_ completion: @escaping (Track?) -> Void) {
        getInfo?(.main) { [weak self] dictionary in
            guard let self else { return }
            let info = dictionary as? [String: Any] ?? [:]
            func value<T>(_ key: String) -> T? { info["kMRMediaRemoteNowPlayingInfo" + key] as? T }

            guard let title: String = value("Title"), !title.isEmpty else {
                completion(nil)
                return
            }
            let data: Data? = value("ArtworkData")
            if data != self.artworkData {
                self.artworkData = data
                self.artworkImage = data.flatMap(NSImage.init(data:))
            }
            completion(Track(title: title,
                             artist: value("Artist") ?? "",
                             isPlaying: (value("PlaybackRate") ?? 0.0) > 0,
                             duration: value("Duration") ?? 0,
                             elapsed: value("ElapsedTime") ?? 0,
                             measuredAt: value("Timestamp") ?? Date(),
                             artwork: self.artworkImage,
                             appName: self.sourceName,
                             appIcon: self.sourceIcon))
        }
    }

    func send(_ command: Command) {
        _ = sendCommand?(command.rawValue, nil)
    }
}
