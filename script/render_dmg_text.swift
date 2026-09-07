import AppKit

let directory = CommandLine.arguments[1]
let path = directory + "/background.png"
guard let source = NSImage(contentsOfFile: path),
      let font = NSFont(name: "PingFangSC-Regular", size: 34),
      let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: 3200, pixelsHigh: 1760,
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      ),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Required PingFang font or background unavailable")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.shouldAntialias = true
context.cgContext.setAllowsAntialiasing(true)
context.cgContext.scaleBy(x: 2, y: 2)
source.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 880))

let arrowColors: [(CGFloat, CGFloat, CGFloat)] = [(235, 184, 202), (169, 94, 122), (67, 30, 44)]
for (index, color) in arrowColors.enumerated() {
    NSColor(
        srgbRed: color.0 / 255, green: color.1 / 255,
        blue: color.2 / 255, alpha: 1
    ).setStroke()
    let x = CGFloat(762 + index * 34)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: x - 9, y: 880 - 426))
    arrow.line(to: NSPoint(x: x + 4, y: 880 - 444))
    arrow.line(to: NSPoint(x: x - 9, y: 880 - 462))
    arrow.lineWidth = 7
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.stroke()
}

let label = NSMutableAttributedString(
    string: "将 Seal Note 拖入「应用程序」即可安装",
    attributes: [
        .font: font,
        .foregroundColor: NSColor(
            srgbRed: 75 / 255, green: 85 / 255, blue: 101 / 255, alpha: 1
        ),
    ]
)
let string = label.string as NSString
label.addAttribute(
    .font, value: NSFont.systemFont(ofSize: 34, weight: .regular),
    range: string.range(of: "Seal Note")
)
let size = label.size()
label.draw(at: NSPoint(x: (1600 - size.width) / 2, y: 880 - 110 - size.height / 2))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: path)
)
