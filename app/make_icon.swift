// Generates Viska's app icon: a green rounded "squircle" with a white "V",
// rendered at every size macOS needs, into an .iconset folder.
// Usage: make_icon <output.iconset dir>
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Rounded-rect (macOS squircle proportions) with a small margin.
    let margin = s * 0.085
    let rect = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let radius = rect.width * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Green gradient fill.
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let colors = [
        NSColor(srgbRed: 0.22, green: 0.85, blue: 0.44, alpha: 1).cgColor,
        NSColor(srgbRed: 0.09, green: 0.58, blue: 0.28, alpha: 1).cgColor,
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0, 1])!
    cg.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                          end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    cg.restoreGState()

    // White "V".
    let fontSize = s * 0.52
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let str = NSAttributedString(string: "V", attributes: attrs)
    let tsz = str.size()
    // Nudge slightly down to optically center the glyph.
    let origin = CGPoint(x: (s - tsz.width) / 2, y: (s - tsz.height) / 2 - s * 0.015)
    str.draw(at: origin)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: make_icon <dir.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

// pixel size -> iconset filenames
let map: [(Int, [String])] = [
    (16, ["icon_16x16.png"]),
    (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64, ["icon_32x32@2x.png"]),
    (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"]),
]
for (size, names) in map {
    let data = render(size: size)
    for name in names {
        try! data.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
    }
}
print("wrote iconset to \(dir)")
