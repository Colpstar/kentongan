import AppKit
import SwiftUI

/// Drives the opening and closing as one spring, so the blur, the outline and the content move together.
final class SpringAnimator {
    private var value: CGFloat = 0
    private var velocity: CGFloat = 0
    private var target: CGFloat = 0
    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0
    var onChange: (CGFloat) -> Void = { _ in }

    private let stiffness: CGFloat = 260
    private let damping: CGFloat = 26 // just under critical: a small, soft overshoot

    var isAnimating: Bool { timer != nil }

    func move(to newTarget: CGFloat) {
        guard newTarget != target else { return }
        target = newTarget
        guard timer == nil else { return }
        lastTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        let now = CACurrentMediaTime()
        var remaining = CGFloat(min(now - lastTime, 1.0 / 20))
        lastTime = now
        // Small fixed steps keep the spring stable when a frame is late.
        while remaining > 0 {
            let dt = min(remaining, 1.0 / 240)
            velocity += (stiffness * (target - value) - damping * velocity) * dt
            value += velocity * dt
            remaining -= dt
        }
        if abs(target - value) < 0.001 && abs(velocity) < 0.01 {
            value = target
            velocity = 0
            timer?.invalidate()
            timer = nil
        }
        onChange(value)
    }
}

/// The real blur of whatever is behind the window, cut to the island's shape, with SwiftUI on top.
final class GlassContainer: NSView {
    private let blur = NSVisualEffectView()
    private var maskRadius: CGFloat = -1

    init(content: NSView) {
        super.init(frame: NSRect(origin: .zero, size: Layout.window))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        addSubview(blur)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        apply(size: Layout.collapsed, radius: Layout.collapsedRadius)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(size: CGSize, radius: CGFloat) {
        let rounded = radius.rounded()
        if rounded != maskRadius {
            maskRadius = rounded
            blur.maskImage = Self.mask(radius: rounded)
        }
        blur.frame = NSRect(x: (Layout.window.width - size.width) / 2, y: Layout.window.height - size.height,
                            width: size.width, height: size.height)
    }

    /// A tiny stretchable image: the corners keep their shape at any size.
    private static func mask(radius: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: radius * 2 + 1, height: radius + 2), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(NotchShape(radius: radius).path(in: rect).cgPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.capInsets = NSEdgeInsets(top: 1, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
