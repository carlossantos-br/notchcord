import AppKit
// Renders the Notchcord icon: graphite squircle, black island hanging from the top, blurple bubble.
let out = CommandLine.arguments[1]
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S), flipped: true) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    let card = CGRect(x: 100, y: 100, width: 824, height: 824)
    let sq = NSBezierPath(roundedRect: card, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSGradient(colors: [NSColor(calibratedWhite: 0.20, alpha: 1), NSColor(calibratedWhite: 0.08, alpha: 1)])!
        .draw(in: sq, angle: 90)
    ctx.restoreGState()
    sq.addClip()
    // island
    let island = NSBezierPath(roundedRect: CGRect(x: 232, y: 60, width: 560, height: 470), xRadius: 120, yRadius: 120)
    NSColor.black.setFill(); island.fill()
    NSColor(calibratedWhite: 1, alpha: 0.07).setStroke(); island.lineWidth = 6; island.stroke()
    // message lines
    let blurple = NSColor(calibratedRed: 0.345, green: 0.396, blue: 0.949, alpha: 1)
    blurple.setFill()
    NSBezierPath(ovalIn: CGRect(x: 300, y: 300, width: 92, height: 92)).fill()
    NSColor(calibratedWhite: 1, alpha: 0.9).setFill()
    NSBezierPath(roundedRect: CGRect(x: 418, y: 312, width: 250, height: 30), xRadius: 15, yRadius: 15).fill()
    NSColor(calibratedWhite: 1, alpha: 0.45).setFill()
    NSBezierPath(roundedRect: CGRect(x: 418, y: 360, width: 180, height: 26), xRadius: 13, yRadius: 13).fill()
    // notch camera
    NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: 490, y: 150, width: 44, height: 44)).fill()
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
