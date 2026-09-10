import AppKit
import SwiftUI

/// SwiftUI owns the process lifecycle; AppKit owns the single Landline window.
/// The outer frame is locked to the Figma canvas: 320 × 672 points.
@main
struct LandlineMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            IrohSettingsView(iroh: appDelegate.iroh)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let designSize = NSSize(width: 320, height: 672)
    let iroh = IrohClient()
    private var window: NSWindow?
    private var visualRoot: LandlineVisualRootView?
    private var trafficHost: TrafficLightHostView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            NSLog("Landline: macOS Reduce Transparency is enabled; native backdrop blur is suppressed by the OS.")
        } else {
            NSLog("Landline: macOS Reduce Transparency is OFF; native backdrop blur should be visible.")
        }

        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: visibleFrame.midX - designSize.width / 2,
            y: visibleFrame.midY - designSize.height / 2
        )
        let outerFrame = NSRect(origin: origin, size: designSize)

        // Keep .resizable in the style mask so AppKit supplies the normal active
        // green standard-window-button appearance. The actual window is locked
        // below with identical minimum/maximum frame sizes and full screen is
        // disabled, so the Landline canvas remains exactly 320 × 672.
        let style: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]

        let contentRect = NSWindow.contentRect(forFrameRect: outerFrame, styleMask: style)
        let landlineWindow = NSWindow(
            contentRect: contentRect,
            styleMask: style,
            backing: .buffered,
            defer: false
        )

        landlineWindow.delegate = self
        landlineWindow.title = "Landline"
        landlineWindow.titleVisibility = .hidden
        landlineWindow.titlebarAppearsTransparent = true
        landlineWindow.titlebarSeparatorStyle = .none
        landlineWindow.toolbar = nil

        // Lock the outer AppKit frame to the fixed Figma canvas while retaining
        // native standard-button styling from a resizable window style.
        landlineWindow.minSize = designSize
        landlineWindow.maxSize = designSize
        landlineWindow.collectionBehavior.insert(.fullScreenNone)

        // A behind-window NSVisualEffectView only works as intended when the
        // containing window itself contributes no opaque backing surface.
        landlineWindow.backgroundColor = .clear
        landlineWindow.isOpaque = false
        landlineWindow.hasShadow = true
        landlineWindow.isMovable = true
        landlineWindow.isMovableByWindowBackground = false
        landlineWindow.animationBehavior = .documentWindow
        landlineWindow.isReleasedWhenClosed = false
        landlineWindow.representedURL = nil

        // Native glass now lives *inside the actual Landline window*. Previous
        // passes used a separate borderless child window underneath SwiftUI;
        // that arrangement made backdrop sampling fragile. Here the hierarchy
        // is deliberately simple:
        //
        // NSWindow (clear/non-opaque)
        // └─ LandlineVisualRootView (rounded clip)
        //    ├─ NSVisualEffectView (.behindWindow)
        //    ├─ #ABABAB @ 60% tint
        //    ├─ SwiftUI interface (transparent root)
        //    └─ native traffic-light host
        let root = LandlineVisualRootView(frame: NSRect(origin: .zero, size: designSize))
        let hostingView = TransparentHostingView(
            rootView: ContentView(
                iroh: iroh,
                onModalPresentationChanged: { [weak self] isPresented in
                    self?.trafficHost?.setModalPresentation(isPresented)
                }
            )
        )
        hostingView.frame = root.bounds
        hostingView.autoresizingMask = [.width, .height]
        root.installHostingView(hostingView)
        landlineWindow.contentView = root
        landlineWindow.setFrame(outerFrame, display: false)

        self.visualRoot = root
        self.window = landlineWindow

        // Do not re-parent the window-owned traffic lights. AppKit may rebuild
        // its title-bar/theme-frame hierarchy over a long-running session and
        // reclaim those instances. Instead, hide AppKit's originals and create
        // independent native standard buttons intended for a caller-owned view.
        installNativeWindowButtons()

        landlineWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
        logWindowGeometry()
        landlineWindow.invalidateShadow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        iroh.stop()
    }

    func windowDidResize(_ notification: Notification) {
        positionTrafficHost()
        window?.invalidateShadow()
    }

    func windowDidMove(_ notification: Notification) {
        // Backdrop sampling now occurs inside the real window, so there is no
        // secondary child-window frame to keep in sync while moving.
    }

    private func installNativeWindowButtons() {
        guard let window,
              let container = window.contentView
        else { return }

        let host = TrafficLightHostView(frame: .zero)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(host, positioned: .above, relativeTo: nil)
        trafficHost = host
        positionTrafficHost()

        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        // Leave the genuine window-owned instances in AppKit's title-bar
        // hierarchy. Hiding them avoids duplicate traffic lights while allowing
        // AppKit to continue owning/rebuilding its private theme-frame contents.
        types.forEach { window.standardWindowButton($0)?.isHidden = true }

        // This type method returns *new* native standard buttons sized for the
        // requested window style. AppKit documents these as caller-owned: we add
        // them to our hierarchy and point their existing native actions at this
        // Landline window rather than stealing the theme-frame instances.
        let buttons = types.compactMap { type -> NSButton? in
            guard let button = NSWindow.standardWindowButton(type, for: window.styleMask) else {
                return nil
            }

            button.target = window
            button.translatesAutoresizingMaskIntoConstraints = true
            button.autoresizingMask = []
            button.isHidden = false
            button.isEnabled = true
            host.addSubview(button)
            return button
        }

        if buttons.count != types.count {
            NSLog("Landline: expected 3 detached native traffic-light buttons, got %ld", buttons.count)
        }

        host.buttons = buttons
        host.installHoverOverlay()
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
    }

    private func positionTrafficHost() {
        guard let window,
              let container = window.contentView,
              let trafficHost
        else { return }

        // Figma backing: x=24, y=24, w=64, h=24. AppKit views are normally
        // bottom-left based; account for either coordinate orientation.
        let y: CGFloat = container.isFlipped ? 24 : container.bounds.height - 48
        trafficHost.frame = NSRect(x: 24, y: y, width: 64, height: 24)
        trafficHost.needsLayout = true
        trafficHost.layoutSubtreeIfNeeded()
    }

    private func logWindowGeometry() {
        guard let window else { return }
        let content = window.contentView?.bounds.size ?? .zero
        NSLog(
            "Landline geometry — outer: %.1f × %.1f, full-size content: %.1f × %.1f",
            window.frame.width,
            window.frame.height,
            content.width,
            content.height
        )

        if let visualRoot {
            let effect = visualRoot.effectView
            NSLog(
                "Landline native glass — active=%@, behindWindow=%@, material=underWindowBackground, effectAlpha=%.2f, tintAlpha=0.06, edgeMask=none, frame=%.1f × %.1f",
                effect.state == .active ? "YES" : "NO",
                effect.blendingMode == .behindWindow ? "YES" : "NO",
                effect.alphaValue,
                effect.bounds.width,
                effect.bounds.height
            )
        }
    }
}

/// The real window background stack. The wrapper deliberately stays *non*
/// layer-backed: layer-flattening a parent around a behind-window visual effect
/// can substantially reduce the visible backdrop contribution. The effect is
/// masked directly instead, while SwiftUI remains a fully opaque sibling above
/// the glass stack.
private final class LandlineVisualRootView: NSView {
    let effectView: NSVisualEffectView
    private let tintView: NSView

    // Keep most of the native visual effect strength so the blur remains clear,
    // but allow a little more direct backdrop contribution than v4. The custom
    // grey wash is reduced at the same time to move closer to the Figma reference.
    private let effectOpacity: CGFloat = 1.00
    private let tintOpacity: CGFloat = 0.06

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frameRect.size))
        tintView = NSView(frame: NSRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)

        // Do not make this wrapper layer-backed and do not clip it. The visual
        // effect owns its own rounded mask so WindowServer can keep sampling
        // the desktop/other windows directly behind Landline.
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = false
        effectView.alphaValue = effectOpacity
        // Match the canonical browser shell radius without layer-flattening the
        // parent view around the behind-window effect. A continuous layer clip
        // on the effect itself leaves the proven window hierarchy unchanged.
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 24
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        addSubview(effectView)

        // The under-window material remains dominant enough to soften detail, while
        // this very light neutral-grey overlay lets substantially more of the
        // backdrop colour and tonal variation remain visible.
        tintView.wantsLayer = true
        tintView.layer?.isOpaque = false
        tintView.layer?.backgroundColor = NSColor(
            srgbRed: 171.0 / 255.0,
            green: 171.0 / 255.0,
            blue: 171.0 / 255.0,
            alpha: tintOpacity
        ).cgColor
        tintView.layer?.cornerRadius = 24
        tintView.layer?.cornerCurve = .continuous
        tintView.layer?.masksToBounds = true
        tintView.autoresizingMask = [.width, .height]
        addSubview(tintView, positioned: .above, relativeTo: effectView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func installHostingView<Content: View>(_ hostingView: NSHostingView<Content>) {
        addSubview(hostingView, positioned: .above, relativeTo: tintView)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        effectView.state = .active
    }
}

/// Hosts three caller-owned native NSWindow standard buttons in the 64 × 24
/// Figma control region. The window's genuine theme-frame buttons remain hidden
/// in their AppKit-owned hierarchy instead of being re-parented here.
private final class TrafficLightHostView: NSView {
    var buttons: [NSButton] = []
    private var hoverTrackingArea: NSTrackingArea?
    private let hoverOverlay = TrafficLightHoverOverlayView(frame: .zero)

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    func setModalPresentation(_ isPresented: Bool) {
        // Keep the proven native controls installed and clickable. Only their
        // pixels are suppressed while SwiftUI displays a blurred proxy beneath.
        let visualAlpha: CGFloat = isPresented ? 0 : 1
        buttons.forEach { $0.alphaValue = visualAlpha }
        hoverOverlay.alphaValue = visualAlpha
        if isPresented {
            hoverOverlay.isHovering = false
        }
    }

    func installHoverOverlay() {
        hoverOverlay.removeFromSuperview()
        hoverOverlay.frame = bounds
        hoverOverlay.autoresizingMask = [.width, .height]
        addSubview(hoverOverlay, positioned: .above, relativeTo: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        hoverOverlay.isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverOverlay.isHovering = false
    }

    override func layout() {
        super.layout()

        // Figma traffic group: 52 × 12 inset 6 pt in the 64 × 24 backing.
        // Native buttons keep their AppKit-supplied size; their centres are
        // fixed at x=12/32/52 and y=12 within this host.
        let centersX: [CGFloat] = [12, 32, 52]
        for (button, centerX) in zip(buttons, centersX) {
            let size = button.frame.size
            button.setFrameOrigin(NSPoint(
                x: round(centerX - size.width / 2),
                y: round(12 - size.height / 2)
            ))
        }

        hoverOverlay.frame = bounds
    }
}

/// Detached standard window buttons keep AppKit's native coloured circles and
/// click behavior, but AppKit's group-hover glyphs depend on private title-bar
/// coordination. Recreate only those tiny rollover glyphs using public AppKit,
/// in a transparent non-interactive overlay so the real buttons remain clickable.
private final class TrafficLightHoverOverlayView: NSView {
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


private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        // The root AppKit view owns corner clipping. Avoid a second opaque or
        // masking layer between SwiftUI and the visual effect underneath.
        layer?.masksToBounds = false
    }
}
