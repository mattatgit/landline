from pathlib import Path

path = Path("LandlineMac/LandlineMacApp.swift")
text = path.read_text()

old_imports = "import AppKit\nimport SwiftUI\n"
new_imports = "import AppKit\nimport QuartzCore\nimport SwiftUI\n"
if old_imports not in text:
    raise SystemExit("Expected AppKit/SwiftUI imports not found")
text = text.replace(old_imports, new_imports, 1)

old_properties = '''private final class LandlineVisualRootView: NSView {
    let effectView: NSVisualEffectView
    private let tintView: NSView

    // Keep most of the native visual effect strength so the blur remains clear,
'''
new_properties = '''private final class LandlineVisualRootView: NSView {
    let effectView: NSVisualEffectView
    private let tintView: NSView
    private let effectMaskLayer = CALayer()
    private let effectOverscan: CGFloat = 24

    // Keep most of the native visual effect strength so the blur remains clear,
'''
if old_properties not in text:
    raise SystemExit("Expected LandlineVisualRootView properties not found")
text = text.replace(old_properties, new_properties, 1)

old_effect_setup = '''        // Do not make this wrapper layer-backed and do not clip it. The visual
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
'''
new_effect_setup = '''        // Do not make this wrapper layer-backed and do not clip it. Instead,
        // overscan the visual effect beyond the visible window and mask the
        // composited result back to the canonical 24 pt shell. This gives the
        // blur kernel real sampling area outside the visible boundary, avoiding
        // the inset/faded blur edge caused by masksToBounds on the effect itself.
        effectView.autoresizingMask = []
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = false
        effectView.alphaValue = effectOpacity
        effectView.wantsLayer = true

        effectMaskLayer.backgroundColor = NSColor.black.cgColor
        effectMaskLayer.cornerRadius = 24
        effectMaskLayer.cornerCurve = .continuous
        effectView.layer?.mask = effectMaskLayer
        addSubview(effectView)
'''
if old_effect_setup not in text:
    raise SystemExit("Expected visual-effect clipping block not found")
text = text.replace(old_effect_setup, new_effect_setup, 1)

old_tail = '''    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func installHostingView<Content: View>(_ hostingView: NSHostingView<Content>) {
'''
new_tail = '''    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        // The visual effect renders 24 pt beyond each window edge, while its
        // layer mask exposes only the actual 320 × 672 rounded Landline shell.
        // Keeping the mask inset inside the oversized effect prevents the blur
        // kernel from fading toward transparent pixels at the visible boundary.
        effectView.frame = bounds.insetBy(dx: -effectOverscan, dy: -effectOverscan)
        effectMaskLayer.frame = NSRect(
            x: effectOverscan,
            y: effectOverscan,
            width: bounds.width,
            height: bounds.height
        )

        // The tint remains exactly window-sized; it supplies the visible 24 pt
        // shell edge without limiting the backdrop blur's sampling area.
        tintView.frame = bounds
    }

    func installHostingView<Content: View>(_ hostingView: NSHostingView<Content>) {
'''
if old_tail not in text:
    raise SystemExit("Expected LandlineVisualRootView tail not found")
text = text.replace(old_tail, new_tail, 1)

path.write_text(text)
