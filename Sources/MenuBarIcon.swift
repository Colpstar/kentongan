import AppKit

enum MenuBarIcon {
    /// A one-colour kentongan. As a template image, macOS tints it to match the menu bar.
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()

            // Cord.
            let cord = NSBezierPath()
            cord.move(to: NSPoint(x: 6.8, y: 0.8))
            cord.line(to: NSPoint(x: 9, y: 4.2))
            cord.line(to: NSPoint(x: 11.2, y: 0.8))
            cord.lineWidth = 1.2
            cord.lineCapStyle = .round
            cord.lineJoinStyle = .round
            cord.stroke()

            // Body, with the slit left see-through.
            let body = NSBezierPath(roundedRect: NSRect(x: 5.5, y: 3.5, width: 7, height: 14), xRadius: 3, yRadius: 3)
            body.append(NSBezierPath(roundedRect: NSRect(x: 8.1, y: 7.2, width: 1.8, height: 6.6),
                                     xRadius: 0.9, yRadius: 0.9))
            body.windingRule = .evenOdd
            body.fill()

            // Sound waves.
            for (edge, bulge) in [(CGFloat(3.4), CGFloat(1.2)), (14.6, 16.8)] {
                let wave = NSBezierPath()
                wave.move(to: NSPoint(x: edge, y: 7.5))
                wave.curve(to: NSPoint(x: edge, y: 13.5),
                           controlPoint1: NSPoint(x: bulge, y: 9), controlPoint2: NSPoint(x: bulge, y: 12))
                wave.lineWidth = 1.3
                wave.lineCapStyle = .round
                wave.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Kentongan"
        return image
    }
}
