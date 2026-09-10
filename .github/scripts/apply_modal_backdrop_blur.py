from pathlib import Path

path = Path('LandlineMac/ContentView.swift')
text = path.read_text()

old = '''            // Figma "Window/Glass" treatment used behind the profile sheet:\n            // the complete main interface is softened by an 18 pt SwiftUI blur while\n            // the sheet remains crisp above it. This mirrors the Settings view\n            // frames where Window/Glass uses backdrop-blur 25 px.\n            mainInterface\n                .blur(radius: isModalPresented ? 18 : 0)\n                .animation(.easeOut(duration: 0.28), value: showProfile)\n                .animation(.easeOut(duration: 0.10), value: showAddUser)\n\n'''

new = '''            // Keep the main interface geometrically unchanged. Sheet-open blur is\n            // supplied by an edge-to-edge within-window backdrop layer below rather\n            // than SwiftUI's bounded Gaussian blur, which faded inward at the\n            // 320 × 672 render boundary.\n            mainInterface\n\n            ModalBackdropBlurView()\n                .frame(width: 320, height: 672)\n                .opacity(isModalPresented ? 0.62 : 0)\n                .allowsHitTesting(false)\n                .animation(.easeOut(duration: 0.28), value: showProfile)\n                .animation(.easeOut(duration: 0.10), value: showAddUser)\n                .zIndex(19)\n\n'''

if old not in text:
    raise SystemExit('Expected bounded modal blur block not found')
text = text.replace(old, new, 1)

old_comment = '''    /// The complete interface below the modal glass/sheet. Keeping this in a\n    /// single compositing subtree means the 18 pt sheet-open blur is applied\n    /// consistently to the header, avatar dial, status, volume and VU panels.\n'''
new_comment = '''    /// The complete interface below the modal glass/sheet. Sheet-open softening\n    /// is applied by ModalBackdropBlurView above this subtree so the blur reaches\n    /// every window edge without changing the fixed Figma geometry.\n'''
if old_comment not in text:
    raise SystemExit('Expected mainInterface blur comment not found')
text = text.replace(old_comment, new_comment, 1)

marker = 'private struct TrafficLightModalProxy: View {'
if marker not in text:
    raise SystemExit('Expected TrafficLightModalProxy insertion marker not found')

view = '''/// Browser-style backdrop blur for modal/sheet presentation. Unlike SwiftUI\'s\n/// `.blur`, NSVisualEffectView with `.withinWindow` samples the already-rendered\n/// window behind this view instead of blurring a bounded offscreen bitmap.\n/// Keeping the view exactly 320 × 672 therefore avoids the 14 pt inset/fade that\n/// appeared at every edge of the previous sheet-open blur.\nprivate struct ModalBackdropBlurView: NSViewRepresentable {\n    func makeNSView(context: Context) -> NSVisualEffectView {\n        let view = NSVisualEffectView(frame: .zero)\n        view.material = .underWindowBackground\n        view.blendingMode = .withinWindow\n        view.state = .active\n        view.isEmphasized = false\n        return view\n    }\n\n    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {\n        nsView.state = .active\n    }\n}\n\n'''
text = text.replace(marker, view + marker, 1)
path.write_text(text)
