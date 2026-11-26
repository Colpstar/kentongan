// Draws the Kentongan logo and writes every size of the app icon into an .iconset folder.
// Usage: make-icon <output.iconset>
import AppKit

func color(_ hex: Int) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

/// Drawn on a 200 x 200 grid with y pointing down. Small icons drop the thin details.
func draw(_ c: CGContext, small: Bool) {
    func fill(_ path: CGPath, _ hex: Int) {
        c.addPath(path)
        c.setFillColor(color(hex))
        c.fillPath()
    }
    func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
    }
    func stroke(_ path: CGPath, _ hex: Int, _ width: CGFloat) {
        c.addPath(path)
        c.setStrokeColor(color(hex))
        c.setLineWidth(width)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.strokePath()
    }

    c.addPath(rounded(0, 0, 200, 200, 45))
    c.clip()
    let background = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: [color(0x2a5247), color(0x152b26)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(background, start: .zero, end: CGPoint(x: 0, y: 200), options: [])

    // The notch.
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: 45, y: 0))
    notch.addLine(to: CGPoint(x: 155, y: 0))
    notch.addLine(to: CGPoint(x: 155, y: 20))
    notch.addQuadCurve(to: CGPoint(x: 139, y: 36), control: CGPoint(x: 155, y: 36))
    notch.addLine(to: CGPoint(x: 61, y: 36))
    notch.addQuadCurve(to: CGPoint(x: 45, y: 20), control: CGPoint(x: 45, y: 36))
    notch.closeSubpath()
    fill(notch, 0x08100e)

    // Cord.
    let cord = CGMutablePath()
    cord.addLines(between: [CGPoint(x: 88, y: 35), CGPoint(x: 100, y: 55), CGPoint(x: 112, y: 35)])
    stroke(cord, 0xe8d5a8, small ? 7 : 4)

    // Bamboo body with its two knots and the slit that makes the sound.
    let body = rounded(71, 52, 58, 118, 25)
    fill(body, 0xd99a45)
    c.saveGState()
    c.addPath(body)
    c.clip()
    if !small {
        fill(rounded(78, 52, 9, 118, 4), 0xeab566)
    }
    fill(CGPath(rect: CGRect(x: 71, y: 70, width: 58, height: 8), transform: nil), 0x8a5a24)
    fill(CGPath(rect: CGRect(x: 71, y: 146, width: 58, height: 8), transform: nil), 0x8a5a24)
    c.restoreGState()
    fill(rounded(small ? 92 : 93.5, 87, small ? 16 : 13, 50, small ? 8 : 6.5), 0x3a220c)

    // Sound waves.
    let waves: [(CGFloat, CGFloat, CGFloat, CGFloat)] = small
        ? [(48, 34, 88, 136)]
        : [(55, 43, 91, 133), (36, 16, 78, 146)]
    for (edge, bulge, top, bottom) in waves {
        for mirrored in [false, true] {
            let x = { (value: CGFloat) in mirrored ? 200 - value : value }
            let wave = CGMutablePath()
            wave.move(to: CGPoint(x: x(edge), y: top))
            wave.addQuadCurve(to: CGPoint(x: x(edge), y: bottom),
                              control: CGPoint(x: x(bulge), y: (top + bottom) / 2))
            stroke(wave, 0xfbe7b5, small ? 11 : 6)
        }
    }
}

guard CommandLine.arguments.count == 2 else {
    print("usage: make-icon <output.iconset>")
    exit(1)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let c = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        // macOS icons keep a margin around the rounded square: 824 of 1024.
        let unit = CGFloat(pixels) / 1024
        c.translateBy(x: 0, y: CGFloat(pixels))
        c.scaleBy(x: unit, y: -unit)
        c.translateBy(x: 100, y: 100)
        c.scaleBy(x: 824.0 / 200, y: 824.0 / 200)
        draw(c, small: pixels <= 48)
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
