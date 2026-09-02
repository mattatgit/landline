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
    private var refreshingTrafficTracking = false

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
        let hostingView = TransparentHostingView(rootView: ContentView(iroh: iroh))
        hostingView.frame = root.bounds
        hostingView.autoresizingMask = [.width, .height]
        root.installHostingView(hostingView)
        landlineWindow.contentView = root
        landlineWindow.setFrame(outerFrame, display: false)

        self.visualRoot = root
        self.window = landlineWindow

        landlineWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            self?.installNativeWindowButtons()
            self?.refreshNativeButtonTrackingAreas()
            self?.logWindowGeometry()
            self?.window?.invalidateShadow()
        }
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

    func windowDidBecomeMain(_ notification: Notification) {
        // AppKit can rebuild title-bar tracking when a window becomes main.
        // Refresh once more so the native rollover region stays attached to
        // the buttons' custom Figma location.
        DispatchQueue.main.async { [weak self] in
            self?.refreshNativeButtonTrackingAreas()
        }
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
        let buttons = types.compactMap { window.standardWindowButton($0) }

        for button in buttons {
            button.removeFromSuperview()
            button.translatesAutoresizingMaskIntoConstraints = true
            button.autoresizingMask = []
            button.isHidden = false
            button.isEnabled = true
            host.addSubview(button)
        }

        host.buttons = buttons
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()

        // Ask the buttons themselves to rebuild any local tracking first.
        buttons.forEach { $0.updateTrackingAreas() }
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

    /// Re-parenting genuine NSWindow buttons can leave AppKit's old title-bar
    /// rollover tracking rectangle cached. A no-visible-change +1/-1 pt frame
    /// cycle forces AppKit to rebuild that tracking geometry, a long-standing
    /// Cocoa workaround for moved standard window buttons.
    private func refreshNativeButtonTrackingAreas() {
        guard let window, !refreshingTrafficTracking else { return }
        refreshingTrafficTracking = true

        let original = window.frame
        var nudge = original
        nudge.size.width += 1
        window.setFrame(nudge, display: false, animate: false)
        window.setFrame(original, display: false, animate: false)

        positionTrafficHost()
        trafficHost?.buttons.forEach {
            $0.updateTrackingAreas()
            $0.needsDisplay = true
        }
        refreshingTrafficTracking = false
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
        // Let the real NSWindow own the outer rounded clipping. The previous
        // per-view bitmap mask introduced a faint antialiased grey fringe that
        // read as an explicit window stroke.
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

/// Hosts the three *real* NSWindow standard buttons in the 64 × 24 Figma
/// control region. Keeping this view tiny prevents it intercepting any other
/// Landline controls.
private final class TrafficLightHostView: NSView {
    var buttons: [NSButton] = []
    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

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
