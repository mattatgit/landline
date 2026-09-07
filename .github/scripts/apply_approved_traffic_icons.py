from pathlib import Path

source_path = Path("LandlineMac/LandlineMacApp.swift")
text = source_path.read_text()
start_marker = "private final class TrafficLightHoverOverlayView: NSView {"
end_marker = "private final class TransparentHostingView<Content: View>: NSHostingView<Content> {"
start = text.index(start_marker)
end = text.index(end_marker)

replacement = r'''private final class TrafficLightHoverOverlayView: NSView {
    var isHovering = false {
        didSet {
            if oldValue != isHovering {
                needsDisplay = true
            }
        }
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHovering else { return }

        // These are the approved 8 × 8 SVG paths from the hover prototype.
        // Every glyph uses the same bounding box and is positioned from
        // center - 4, keeping all three visual centres aligned exactly with the
        // native traffic-light centres at x=12/32/52, y=12.
        drawCloseGlyph(at: NSPoint(x: 12, y: 12))
        drawMinusGlyph(at: NSPoint(x: 32, y: 12))
        drawMaximiseGlyph(at: NSPoint(x: 52, y: 12))
    }

    private func svgPoint(_ x: CGFloat, _ y: CGFloat, origin: NSPoint) -> NSPoint {
        NSPoint(x: origin.x + x, y: origin.y + y)
    }

    private func drawCloseGlyph(at center: NSPoint) {
        let origin = NSPoint(x: center.x - 4, y: center.y - 4)
        let path = NSBezierPath()
        path.move(to: svgPoint(1.18951, 1.15965, origin: origin))
        path.curve(
            to: svgPoint(2.32134, 1.15965, origin: origin),
            controlPoint1: svgPoint(1.50176, 0.84721, origin: origin),
            controlPoint2: svgPoint(2.00914, 0.847136, origin: origin)
        )
        path.line(to: svgPoint(4.0108, 2.85204, origin: origin))
        path.line(to: svgPoint(5.67877, 1.18309, origin: origin))
        path.curve(
            to: svgPoint(6.80963, 1.18309, origin: origin),
            controlPoint1: svgPoint(5.99096, 0.87075, origin: origin),
            controlPoint2: svgPoint(6.49742, 0.870771, origin: origin)
        )
        path.curve(
            to: svgPoint(6.80963, 2.31493, origin: origin),
            controlPoint1: svgPoint(7.12177, 1.49558, origin: origin),
            controlPoint2: svgPoint(7.12156, 2.00231, origin: origin)
        )
        path.line(to: svgPoint(5.14166, 3.98387, origin: origin))
        path.line(to: svgPoint(6.84088, 5.68504, origin: origin))
        path.curve(
            to: svgPoint(6.84088, 6.81688, origin: origin),
            controlPoint1: svgPoint(7.15281, 5.99761, origin: origin),
            controlPoint2: svgPoint(7.1529, 6.50437, origin: origin)
        )
        path.curve(
            to: svgPoint(5.71002, 6.81688, origin: origin),
            controlPoint1: svgPoint(6.52866, 7.12931, origin: origin),
            controlPoint2: svgPoint(6.02224, 7.12929, origin: origin)
        )
        path.line(to: svgPoint(4.0108, 5.11571, origin: origin))
        path.line(to: svgPoint(2.29009, 6.84032, origin: origin))
        path.curve(
            to: svgPoint(1.15826, 6.84032, origin: origin),
            controlPoint1: svgPoint(1.97785, 7.15291, origin: origin),
            controlPoint2: svgPoint(1.47051, 7.15291, origin: origin)
        )
        path.curve(
            to: svgPoint(1.15923, 5.70848, origin: origin),
            controlPoint1: svgPoint(0.846424, 6.52773, origin: origin),
            controlPoint2: svgPoint(0.847225, 6.02096, origin: origin)
        )
        path.line(to: svgPoint(2.88091, 3.98387, origin: origin))
        path.line(to: svgPoint(1.19048, 2.29149, origin: origin))
        path.curve(
            to: svgPoint(1.18951, 1.15965, origin: origin),
            controlPoint1: svgPoint(0.878488, 1.97898, origin: origin),
            controlPoint2: svgPoint(0.877595, 1.47221, origin: origin)
        )
        path.close()

        NSColor(
            srgbRed: 139.0 / 255.0,
            green: 39.0 / 255.0,
            blue: 45.0 / 255.0,
            alpha: 1
        ).setFill()
        path.fill()
    }

    private func drawMinusGlyph(at center: NSPoint) {
        let origin = NSPoint(x: center.x - 4, y: center.y - 4)
        let path = NSBezierPath()
        path.move(to: svgPoint(1.25, 4.75, origin: origin))
        path.curve(
            to: svgPoint(0.5, 4.0, origin: origin),
            controlPoint1: svgPoint(0.835786, 4.75, origin: origin),
            controlPoint2: svgPoint(0.5, 4.41421, origin: origin)
        )
        path.curve(
            to: svgPoint(1.25, 3.25, origin: origin),
            controlPoint1: svgPoint(0.5, 3.58579, origin: origin),
            controlPoint2: svgPoint(0.835786, 3.25, origin: origin)
        )
        path.line(to: svgPoint(6.75, 3.25, origin: origin))
        path.curve(
            to: svgPoint(7.5, 4.0, origin: origin),
            controlPoint1: svgPoint(7.16421, 3.25, origin: origin),
            controlPoint2: svgPoint(7.5, 3.58579, origin: origin)
        )
        path.curve(
            to: svgPoint(6.75, 4.75, origin: origin),
            controlPoint1: svgPoint(7.5, 4.41421, origin: origin),
            controlPoint2: svgPoint(7.16421, 4.75, origin: origin)
        )
        path.line(to: svgPoint(1.25, 4.75, origin: origin))
        path.close()

        NSColor(
            srgbRed: 111.0 / 255.0,
            green: 78.0 / 255.0,
            blue: 0,
            alpha: 1
        ).setFill()
        path.fill()
    }

    private func drawMaximiseGlyph(at center: NSPoint) {
        let origin = NSPoint(x: center.x - 4, y: center.y - 4)
        let path = NSBezierPath()

        path.move(to: svgPoint(6.6582, 2.7373, origin: origin))
        path.curve(
            to: svgPoint(7.0, 2.87793, origin: origin),
            controlPoint1: svgPoint(6.78406, 2.61132, origin: origin),
            controlPoint2: svgPoint(6.99964, 2.7, origin: origin)
        )
        path.line(to: svgPoint(7.0, 6.7998, origin: origin))
        path.curve(
            to: svgPoint(6.7998, 7.0, origin: origin),
            controlPoint1: svgPoint(7.0, 6.91026, origin: origin),
            controlPoint2: svgPoint(6.91026, 7.0, origin: origin)
        )
        path.line(to: svgPoint(2.88281, 7.0, origin: origin))
        path.curve(
            to: svgPoint(2.74121, 6.6582, origin: origin),
            controlPoint1: svgPoint(2.70468, 7.0, origin: origin),
            controlPoint2: svgPoint(2.61532, 6.78423, origin: origin)
        )
        path.line(to: svgPoint(6.6582, 2.7373, origin: origin))
        path.close()

        path.move(to: svgPoint(5.11719, 1.0, origin: origin))
        path.curve(
            to: svgPoint(5.25879, 1.34082, origin: origin),
            controlPoint1: svgPoint(5.2953, 1.0, origin: origin),
            controlPoint2: svgPoint(5.38462, 1.21479, origin: origin)
        )
        path.line(to: svgPoint(1.3418, 5.2627, origin: origin))
        path.curve(
            to: svgPoint(1.0, 5.12109, origin: origin),
            controlPoint1: svgPoint(1.21583, 5.38879, origin: origin),
            controlPoint2: svgPoint(1.0, 5.29932, origin: origin)
        )
        path.line(to: svgPoint(1.0, 1.2002, origin: origin))
        path.curve(
            to: svgPoint(1.2002, 1.0, origin: origin),
            controlPoint1: svgPoint(1.0, 1.08974, origin: origin),
            controlPoint2: svgPoint(1.08974, 1.0, origin: origin)
        )
        path.line(to: svgPoint(5.11719, 1.0, origin: origin))
        path.close()

        NSColor(
            srgbRed: 0,
            green: 101.0 / 255.0,
            blue: 37.0 / 255.0,
            alpha: 1
        ).setFill()
        path.fill()
    }
}
'''

source_path.write_text(text[:start] + replacement + "\n\n" + text[end:])

current_path = Path("docs/CURRENT.md")
current = current_path.read_text()
anchor = "- disables full-screen behavior with `.fullScreenNone`."
addition = "\n- recreates traffic-light group-hover glyphs in a non-interactive public-AppKit overlay using the approved centered 8 × 8 SVG-derived X, minus and maximise vector paths/colors."
if addition.strip() not in current:
    current = current.replace(anchor, anchor + addition)
current_path.write_text(current)
