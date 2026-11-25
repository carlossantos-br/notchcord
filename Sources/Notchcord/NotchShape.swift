import SwiftUI

/// Notch shape: concave "ears" at the top (blending into the screen edge) and convex bottom corners.
struct NotchShape: Shape {
    var ear: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottom) }
        set { ear = newValue.first; bottom = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let e = min(ear, w / 4, h / 2)
        let b = min(bottom, (w - 2 * e) / 2, h - e)
        let x0 = r.minX + e, x1 = r.minX + w - e
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: x0, y: r.minY + e), control: CGPoint(x: x0, y: r.minY))
        p.addLine(to: CGPoint(x: x0, y: r.minY + h - b))
        p.addQuadCurve(to: CGPoint(x: x0 + b, y: r.minY + h), control: CGPoint(x: x0, y: r.minY + h))
        p.addLine(to: CGPoint(x: x1 - b, y: r.minY + h))
        p.addQuadCurve(to: CGPoint(x: x1, y: r.minY + h - b), control: CGPoint(x: x1, y: r.minY + h))
        p.addLine(to: CGPoint(x: x1, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.minX + w, y: r.minY), control: CGPoint(x: x1, y: r.minY))
        p.closeSubpath()
        return p
    }
}
