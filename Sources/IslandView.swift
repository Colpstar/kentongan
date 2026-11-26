import SwiftUI

struct Note: Equatable {
    var title: String
    var subtitle: String
    var body: String
    var app: SourceApp?

    init(texts: [String]) {
        title = texts.first ?? "Notifikasi"
        subtitle = texts.count > 2 ? texts[1] : ""
        body = texts.count > 2 ? texts.dropFirst(2).joined(separator: " ") : (texts.count == 2 ? texts[1] : "")
    }
}

final class IslandModel: ObservableObject {
    @Published var note: Note?
    @Published var expanded = false
    @Published var trusted = true
    @Published var track: Track?
    /// A new notification takes the island over until it times out.
    @Published var showingNote = false
    /// Playback buttons.
    var send: (NowPlaying.Command) -> Void = { _ in }
    /// Notifications still waiting for their turn.
    @Published var waiting = 0
    var openNote: () -> Void = {}
    /// How far open the island is, from the spring: 0 closed, 1 open, a little past 1 while settling.
    @Published var openness: CGFloat = 0
}

enum Layout {
    static let collapsed = CGSize(width: 190, height: 26)
    static let expanded = CGSize(width: 400, height: 96)
    /// The window never resizes; only the black shape inside it does.
    static let window = CGSize(width: 440, height: 110)
    static let collapsedRadius: CGFloat = 13
    static let expandedRadius: CGFloat = 28

    static func size(at openness: CGFloat) -> CGSize {
        CGSize(width: min(collapsed.width + (expanded.width - collapsed.width) * openness, window.width),
               height: min(collapsed.height + (expanded.height - collapsed.height) * openness, window.height))
    }

    static func radius(at openness: CGFloat) -> CGFloat {
        collapsedRadius + (expandedRadius - collapsedRadius) * min(max(openness, 0), 1)
    }
}

/// Light on top of the blur: a soft tint for contrast and a bright edge, like a pane of glass.
struct GlassSurface: View {
    var radius: CGFloat

    var body: some View {
        let shape = NotchShape(radius: radius)
        ZStack {
            shape.fill(LinearGradient(colors: [Color.black.opacity(0.28), Color.black.opacity(0.10)],
                                      startPoint: .top, endPoint: .bottom))
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.0), Color.white.opacity(0.08)],
                                      startPoint: .center, endPoint: .bottom))
            shape.stroke(LinearGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.32)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }
}

/// Flat on top (it hangs from the screen edge), rounded at the bottom.
struct NotchShape: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let openness = model.openness
        let size = Layout.size(at: openness)
        let radius = Layout.radius(at: openness)
        ZStack {
            GlassSurface(radius: radius)
            if let track = model.track, track.isPlaying {
                HStack {
                    artwork(track, side: 18, corner: 5)
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 12)
                .frame(width: size.width)
                .opacity(Double(max(0, 1 - openness * 3)))
            }
            // Laid out at its final size so text never reflows; it fades and grows in with the glass.
            ZStack {
                content
                    .id(contentKey)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                            removal: .opacity))
            }
            .animation(.easeInOut(duration: 0.28), value: contentKey)
            .padding(.horizontal, 20)
            .frame(width: Layout.expanded.width, height: Layout.expanded.height)
            .scaleEffect(0.92 + 0.08 * min(openness, 1), anchor: .top)
            .opacity(Double(min(max((openness - 0.35) / 0.55, 0), 1)))
            .allowsHitTesting(model.expanded)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(NotchShape(radius: radius))
        .frame(width: Layout.window.width, height: Layout.window.height, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    /// Changes when a different thing is shown, which is what gets cross-faded.
    private var contentKey: String {
        if !model.trusted { return "permission" }
        if let note = model.note, model.showingNote || model.track == nil {
            return "note" + note.title + note.subtitle + note.body
        }
        if let track = model.track { return "track" + track.identity }
        return "empty"
    }

    @ViewBuilder private var content: some View {
        if !model.trusted {
            row(icon: "lock.fill", title: "Butuh izin Accessibility",
                subtitle: "", body: "System Settings → Privacy & Security → Accessibility → NotchProto")
        } else if let note = model.note, model.showingNote || model.track == nil {
            row(icon: "bell.fill", app: note.app, title: note.title, subtitle: note.subtitle, body: note.body)
                .overlay(alignment: .topTrailing) {
                    if model.waiting > 0 {
                        Text("+\(model.waiting)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.openNote() }
        } else if let track = model.track {
            player(track)
        } else {
            row(icon: "bell", title: "Belum ada notifikasi", subtitle: "", body: "Notifikasi baru muncul di sini.")
        }
    }

    private func player(_ track: Track) -> some View {
        HStack(spacing: 12) {
            artwork(track, side: 58, corner: 11)
            VStack(alignment: .leading, spacing: 2) {
                if !track.appName.isEmpty {
                    HStack(spacing: 4) {
                        if let icon = track.appIcon {
                            Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                        }
                        Text(track.appName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    GeometryReader { area in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule().fill(Color.white)
                                .frame(width: area.size.width * track.progress(at: context.date))
                        }
                    }
                    .frame(height: 3)
                }
                .padding(.top, 4)
            }
            HStack(spacing: 2) {
                control("backward.fill", size: 13, command: .previous)
                control(track.isPlaying ? "pause.fill" : "play.fill", size: 19, command: .togglePlayPause)
                control("forward.fill", size: 13, command: .next)
            }
        }
    }

    private func control(_ icon: String, size: CGFloat, command: NowPlaying.Command) -> some View {
        Button { model.send(command) } label: {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundColor(.white)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func artwork(_ track: Track, side: CGFloat, corner: CGFloat) -> some View {
        if let image = track.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: corner))
        } else if let icon = track.appIcon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: side, height: side)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: side * 0.5, weight: .medium))
                .foregroundColor(.white)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: corner).fill(Color.white.opacity(0.14)))
        }
    }

    private func row(icon: String, app: SourceApp? = nil, title: String, subtitle: String,
                     body text: String) -> some View {
        HStack(spacing: 12) {
            if let app {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 46, height: 46)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.14)))
            }
            VStack(alignment: .leading, spacing: 2) {
                // Skipped when the title already is the app name, or all three lines are in use.
                if let app, subtitle.isEmpty, app.name != title {
                    Text(app.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(subtitle.isEmpty && app == nil ? 2 : 1)
            }
            Spacer(minLength: 0)
        }
    }
}
