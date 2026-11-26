// Renders the README demo GIF from the app's own island view, with made-up sample data.
// It is not a screen recording: the backdrop is drawn and the blur is imitated.
// Run from the project folder: ./scripts/make-demo.sh
import ImageIO
import SwiftUI

private let framesPerSecond = 20.0

private struct Scene: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.42, green: 0.24, blue: 0.55), Color(red: 0.12, green: 0.42, blue: 0.47)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.orange.opacity(0.55)).frame(width: 130, height: 130).offset(x: -150, y: 40)
            Circle().fill(Color.pink.opacity(0.4)).frame(width: 90, height: 90).offset(x: 170, y: 20)
            Rectangle().fill(Color.black.opacity(0.22)).frame(height: 22)
            // Stands in for the system blur.
            NotchShape(radius: Layout.radius(at: model.openness))
                .fill(Color(white: 0.08).opacity(0.62))
                .frame(width: Layout.size(at: model.openness).width, height: Layout.size(at: model.openness).height)
            IslandView(model: model)
        }
        .frame(width: 520, height: 150, alignment: .top)
        .clipped()
    }
}

@main
struct MakeDemo {
    @MainActor static func main() {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns")!
        let model = IslandModel()
        model.track = Track(title: "Senja di Kampung", artist: "Band Contoh", isPlaying: true,
                            duration: 214, elapsed: 72, measuredAt: Date(), artwork: nil,
                            appName: "Pemutar Musik", appIcon: icon)
        var note = Note(texts: ["Pak RT", "Nanti malam ronda ya, jangan lupa bawa kentongan"])
        note.app = SourceApp(name: "Pesan", url: URL(fileURLWithPath: "/"), icon: icon)
        model.note = note

        // (seconds, island open, showing the notification)
        let script: [(Double, Bool, Bool)] = [
            (1.2, false, false), (3.0, true, true), (2.8, true, false), (0.9, false, false),
        ]

        var frames: [CGImage] = []
        var openness: CGFloat = 0
        var velocity: CGFloat = 0
        for (seconds, open, showingNote) in script {
            model.expanded = open
            model.showingNote = showingNote
            for _ in 0..<Int(seconds * framesPerSecond) {
                // The same spring as SpringAnimator.
                for _ in 0..<12 {
                    let dt = CGFloat(1 / framesPerSecond / 12)
                    velocity += (260 * ((open ? 1 : 0) - openness) - 26 * velocity) * dt
                    openness += velocity * dt
                }
                model.openness = openness
                let renderer = ImageRenderer(content: Scene(model: model).environment(\.colorScheme, .dark))
                renderer.scale = 1.5
                frames.append(renderer.cgImage!)
            }
        }

        let gif = CGImageDestinationCreateWithURL(output as CFURL, "com.compuserve.gif" as CFString, frames.count, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(gif, frame, [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFDelayTime: 1 / framesPerSecond]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { fatalError("could not write the GIF") }

        // A few stills, to check the result.
        if CommandLine.arguments.count > 2 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[2])
            for index in [10, 28, 70, 130] where index < frames.count {
                let png = NSBitmapImageRep(cgImage: frames[index]).representation(using: .png, properties: [:])!
                try? png.write(to: folder.appendingPathComponent("frame\(index).png"))
            }
        }
        print("\(frames.count) frames")
    }
}
