from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"Expected source block not found: {label}")
    return text.replace(old, new, 1)


# Design token: keep existing panels untouched, but make the dial
# match the canonical V22 --onyx value exactly (#1D1E1D).
tokens_path = Path("LandlineMac/DesignTokens.swift")
tokens = tokens_path.read_text()
tokens = replace_once(
    tokens,
    "    static let panel = Color(red: 0.08, green: 0.085, blue: 0.083)\n",
    "    static let dial = Color(red: 29.0 / 255.0, green: 30.0 / 255.0, blue: 29.0 / 255.0) // #1D1E1D\n"
    "    static let panel = Color(red: 0.08, green: 0.085, blue: 0.083)\n",
    "dial colour token",
)
tokens_path.write_text(tokens)


content_path = Path("LandlineMac/ContentView.swift")
text = content_path.read_text()

text = replace_once(
    text,
    "struct ContentView: View {\n    @ObservedObject var iroh: IrohClient\n",
    "struct ContentView: View {\n"
    "    @ObservedObject var iroh: IrohClient\n"
    "    var onModalPresentationChanged: (Bool) -> Void = { _ in }\n",
    "modal presentation callback",
)

text = replace_once(
    text,
    ".blur(radius: isModalPresented ? 25 : 0)",
    ".blur(radius: isModalPresented ? 18 : 0)",
    "sheet blur radius",
)
text = text.replace("softened by a 25 pt blur", "softened by an 18 pt SwiftUI blur", 1)
text = text.replace(
    "single compositing subtree means the 25 pt sheet-open blur",
    "single compositing subtree means the 18 pt sheet-open blur",
    1,
)

text = replace_once(
    text,
    "        .ignoresSafeArea()\n        .task {\n",
    "        .ignoresSafeArea()\n"
    "        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))\n"
    "        .task {\n",
    "24 point outer SwiftUI clip",
)

text = replace_once(
    text,
    "        .onChange(of: volume) { _, newValue in\n"
    "            iroh.setOutputVolume(newValue)\n"
    "        }\n"
    "        .onChange(of: iroh.localTransmitGranted) { _, granted in\n",
    "        .onChange(of: volume) { _, newValue in\n"
    "            iroh.setOutputVolume(newValue)\n"
    "        }\n"
    "        .onChange(of: isModalPresented) { _, presented in\n"
    "            onModalPresentationChanged(presented)\n"
    "        }\n"
    "        .onChange(of: iroh.localTransmitGranted) { _, granted in\n",
    "modal presentation change hook",
)

text = replace_once(
    text,
    "        .onDisappear {\n"
    "            networkPumpTask?.cancel()\n"
    "            addUserFeedbackTask?.cancel()\n"
    "            iroh.stop()\n"
    "        }\n",
    "        .onDisappear {\n"
    "            networkPumpTask?.cancel()\n"
    "            addUserFeedbackTask?.cancel()\n"
    "            onModalPresentationChanged(false)\n"
    "            iroh.stop()\n"
    "        }\n",
    "modal presentation reset",
)

text = replace_once(
    text,
    "            RoundedRectangle(cornerRadius: 8, style: .continuous)\n"
    "                .fill(Color.black.opacity(0.20))\n"
    "                .frame(width: 64, height: 24)\n",
    "            ZStack {\n"
    "                RoundedRectangle(cornerRadius: 8, style: .continuous)\n"
    "                    .fill(Color.black.opacity(0.20))\n\n"
    "                // The real AppKit traffic lights are visually suppressed while\n"
    "                // a sheet is open. This exact-position proxy then receives the\n"
    "                // same SwiftUI blur as the rest of the main interface without\n"
    "                // disturbing the proven caller-owned native button hierarchy.\n"
    "                TrafficLightModalProxy()\n"
    "                    .opacity(isModalPresented ? 1 : 0)\n"
    "            }\n"
    "            .frame(width: 64, height: 24)\n",
    "traffic light modal proxy",
)

text = replace_once(
    text,
    "                BundledImage(name: \"profile_icon\", extension: \"png\")\n"
    "                    .frame(width: 24, height: 24)\n"
    "                    .contentShape(Rectangle())\n",
    "                ProfileButtonArtwork()\n"
    "                    .frame(width: 24, height: 24)\n"
    "                    .contentShape(Rectangle())\n",
    "vector profile artwork",
)

text = replace_once(
    text,
    "            Circle()\n"
    "                .fill(LandlineColor.panel)\n"
    "                .frame(width: 272, height: 272)\n",
    "            Circle()\n"
    "                .fill(LandlineColor.dial)\n"
    "                .frame(width: 272, height: 272)\n",
    "dial fill",
)

marker = "private struct BundledImage: View {"
if marker not in text:
    raise SystemExit("Expected BundledImage insertion marker not found")

vector_views = r'''private struct TrafficLightModalProxy: View {
    var body: some View {
        HStack(spacing: 8) {
            trafficCircle(red: 255, green: 94, blue: 87)
            trafficCircle(red: 255, green: 189, blue: 46)
            trafficCircle(red: 40, green: 200, blue: 64)
        }
        .frame(width: 52, height: 12)
    }

    private func trafficCircle(red: Double, green: Double, blue: Double) -> some View {
        Circle()
            .fill(Color(red: red / 255, green: green / 255, blue: blue / 255))
            .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
            .frame(width: 12, height: 12)
    }
}

/// Vector recreation of the canonical V22 profile-icon.svg. Keeping the
/// original 12 × 13 path geometry avoids scaling a bitmap on Retina Macs.
private struct ProfileButtonArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LandlineColor.dial)

            ProfileGlyph()
                .frame(width: 12, height: 13)
        }
    }
}

private struct ProfileGlyph: View {
    var body: some View {
        Canvas { context, _ in
            var path = Path()

            path.addEllipse(in: CGRect(x: 3.375, y: 0.5, width: 5.25, height: 5.25))

            path.move(to: CGPoint(x: 3.73804, y: 1.79199))
            path.addCurve(
                to: CGPoint(x: 5.17073, y: 2.77810),
                control1: CGPoint(x: 4.14445, y: 2.21367),
                control2: CGPoint(x: 4.63172, y: 2.54906)
            )
            path.addCurve(
                to: CGPoint(x: 6.87504, y: 3.12499),
                control1: CGPoint(x: 5.70973, y: 3.00713),
                control2: CGPoint(x: 6.28939, y: 3.12512)
            )
            path.addCurve(
                to: CGPoint(x: 8.60004, y: 2.76949),
                control1: CGPoint(x: 7.46825, y: 3.12523),
                control2: CGPoint(x: 8.05525, y: 3.00425)
            )

            path.move(to: CGPoint(x: 1.125, y: 11.75))
            path.addCurve(
                to: CGPoint(x: 2.55285, y: 8.30285),
                control1: CGPoint(x: 1.125, y: 10.4571),
                control2: CGPoint(x: 1.63861, y: 9.21709)
            )
            path.addCurve(
                to: CGPoint(x: 6.0, y: 6.875),
                control1: CGPoint(x: 3.46709, y: 7.38861),
                control2: CGPoint(x: 4.70707, y: 6.875)
            )
            path.addCurve(
                to: CGPoint(x: 9.44715, y: 8.30285),
                control1: CGPoint(x: 7.29293, y: 6.875),
                control2: CGPoint(x: 8.53291, y: 7.38861)
            )
            path.addCurve(
                to: CGPoint(x: 10.875, y: 11.75),
                control1: CGPoint(x: 10.3614, y: 9.21709),
                control2: CGPoint(x: 10.875, y: 10.4571)
            )

            path.move(to: CGPoint(x: 4.125, y: 7.24951))
            path.addLine(to: CGPoint(x: 4.125, y: 7.62501))
            path.addCurve(
                to: CGPoint(x: 4.67417, y: 8.95084),
                control1: CGPoint(x: 4.125, y: 8.12229),
                control2: CGPoint(x: 4.32254, y: 8.59921)
            )
            path.addCurve(
                to: CGPoint(x: 6.0, y: 9.50001),
                control1: CGPoint(x: 5.02581, y: 9.30247),
                control2: CGPoint(x: 5.50272, y: 9.50001)
            )
            path.addCurve(
                to: CGPoint(x: 7.32583, y: 8.95084),
                control1: CGPoint(x: 6.49728, y: 9.50001),
                control2: CGPoint(x: 6.97419, y: 9.30247)
            )
            path.addCurve(
                to: CGPoint(x: 7.875, y: 7.62501),
                control1: CGPoint(x: 7.67746, y: 8.59921),
                control2: CGPoint(x: 7.875, y: 8.12229)
            )
            path.addLine(to: CGPoint(x: 7.875, y: 7.24951))

            context.stroke(
                path,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

'''
text = text.replace(marker, vector_views + marker, 1)
content_path.write_text(text)


app_path = Path("LandlineMac/LandlineMacApp.swift")
app = app_path.read_text()

app = replace_once(
    app,
    "        let hostingView = TransparentHostingView(rootView: ContentView(iroh: iroh))\n",
    "        let hostingView = TransparentHostingView(\n"
    "            rootView: ContentView(\n"
    "                iroh: iroh,\n"
    "                onModalPresentationChanged: { [weak self] isPresented in\n"
    "                    self?.trafficHost?.setModalPresentation(isPresented)\n"
    "                }\n"
    "            )\n"
    "        )\n",
    "ContentView chrome callback",
)

app = replace_once(
    app,
    "        effectView.alphaValue = effectOpacity\n"
    "        // Let the real NSWindow own the outer rounded clipping. The previous\n"
    "        // per-view bitmap mask introduced a faint antialiased grey fringe that\n"
    "        // read as an explicit window stroke.\n"
    "        addSubview(effectView)\n",
    "        effectView.alphaValue = effectOpacity\n"
    "        // Match the canonical browser shell radius without layer-flattening the\n"
    "        // parent view around the behind-window effect. A continuous layer clip\n"
    "        // on the effect itself leaves the proven window hierarchy unchanged.\n"
    "        effectView.wantsLayer = true\n"
    "        effectView.layer?.cornerRadius = 24\n"
    "        effectView.layer?.cornerCurve = .continuous\n"
    "        effectView.layer?.masksToBounds = true\n"
    "        addSubview(effectView)\n",
    "24 point native glass corner clip",
)

traffic_marker = "    func installHoverOverlay() {\n"
if traffic_marker not in app:
    raise SystemExit("Expected TrafficLightHostView insertion marker not found")

modal_method = '''    func setModalPresentation(_ isPresented: Bool) {
        // Keep the proven native controls installed and clickable. Only their
        // pixels are suppressed while SwiftUI displays a blurred proxy beneath.
        let visualAlpha: CGFloat = isPresented ? 0 : 1
        buttons.forEach { $0.alphaValue = visualAlpha }
        hoverOverlay.alphaValue = visualAlpha
        if isPresented {
            hoverOverlay.isHovering = false
        }
    }

'''
app = app.replace(traffic_marker, modal_method + traffic_marker, 1)
app_path.write_text(app)
