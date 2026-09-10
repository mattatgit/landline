from pathlib import Path

path = Path('LandlineMac/LandlineMacApp.swift')
text = path.read_text()

old = '''private final class TransparentHostingView<Content: View>: NSHostingView<Content> {\n    override var isOpaque: Bool { false }\n\n    override func viewDidMoveToWindow() {\n'''
new = '''private final class TransparentHostingView<Content: View>: NSHostingView<Content> {\n    override var isOpaque: Bool { false }\n\n    // Landline uses a full-size-content NSWindow and treats the complete\n    // 320 × 672 frame as design space. AppKit still reports a title-bar safe\n    // area to NSHostingView by default, which can inset NSViewRepresentable\n    // children (notably the modal backdrop blur) by roughly 14 pt at the top.\n    // Report no safe-area insets so every full-window SwiftUI/AppKit overlay\n    // shares the exact same canvas as the root visual stack.\n    override var safeAreaInsets: NSEdgeInsets {\n        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)\n    }\n\n    override func viewDidMoveToWindow() {\n'''

if old not in text:
    raise SystemExit('Expected TransparentHostingView block not found')

path.write_text(text.replace(old, new, 1))
