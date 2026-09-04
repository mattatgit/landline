import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var iroh: IrohClient
    @State private var micState: MicState = .muted
    @State private var volume: Double = 0.25
    @State private var hoveredPTT = false
    @State private var hoveredProfile = false
    @State private var hoveredRemoteParticipantID: String?
    @State private var showProfile = false
    @StateObject private var microphone = MicrophoneCapture()
    @State private var pttHeld = false
    @State private var pttCaptureTask: Task<Void, Never>?
    @State private var networkPumpTask: Task<Void, Never>?

    // Profile state. The local user is permanently assigned to the 12 o'clock
    // position. The seven remaining positions are populated only by real peers
    // reported by the Iroh transport; there are no demo/dummy participants anymore.
    @State private var hasProfile = false
    @State private var savedProfileName = ""
    @State private var savedProfileAvatar: NSImage?
    @State private var savedProfileAvatarToken = ""
    @State private var draftProfileName = ""
    @State private var draftProfileAvatar: NSImage?
    @State private var draftProfileAvatarToken = ""
    @State private var currentUserAvatar: NSImage?

    private var isMuted: Bool { micState == .muted }
    private var isTalking: Bool { micState == .talking }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Figma "Window/Glass" treatment used behind the profile sheet:
            // the complete main interface is softened by a 25 pt blur while
            // the sheet remains crisp above it. This mirrors the Settings view
            // frames where Window/Glass uses backdrop-blur 25 px.
            mainInterface
                .blur(radius: showProfile ? 25 : 0)
                .animation(.easeOut(duration: 0.28), value: showProfile)

            // Window/Glass also carries a subtle 10% #F8F8F8 veil. Besides
            // matching the Figma treatment, this view provides the modal hit
            // surface for the exposed area above the bottom sheet.
            Color(red: 248/255, green: 248/255, blue: 248/255)
                .opacity(showProfile ? 0.10 : 0)
                .frame(width: 320, height: 672)
                .contentShape(Rectangle())
                .allowsHitTesting(showProfile)
                .onTapGesture {
                    showProfile = false
                }
                .animation(.easeOut(duration: 0.28), value: showProfile)
                .zIndex(20)

            // Keep the sheet mounted and animate its absolute y-position.
            // Figma open state: y=88, height=584. Hidden state begins just
            // below the 672 pt window, producing a true bottom-sheet motion.
            ProfileSheet(
                hasProfile: hasProfile,
                savedName: savedProfileName,
                savedAvatarToken: savedProfileAvatarToken,
                name: $draftProfileName,
                avatarImage: $draftProfileAvatar,
                avatarToken: $draftProfileAvatarToken,
                onCommit: commitProfile,
                onClose: { showProfile = false }
            )
            .frame(width: 320, height: 584)
            .offset(x: 0, y: showProfile ? 88 : 760)
            .allowsHitTesting(showProfile)
            .animation(.easeOut(duration: 0.28), value: showProfile)
            .zIndex(21)
        }
        .frame(width: 320, height: 672)
        .clipped()
        // The AppKit root view owns the full 320 × 672 window, so SwiftUI
        // should treat every edge as design space rather than reserving title-bar
        // or content-layout safe areas.
        .ignoresSafeArea()
        .task {
            // Restore the local profile before starting the Iroh endpoint so
            // peers immediately receive the persisted name/avatar in `hello`.
            // The store lives in this app's sandbox and is keyed by the stable
            // Landline bundle identifier, so it survives normal Xcode rebuilds.
            let restoredProfile = restorePersistedProfile()

            iroh.setOutputVolume(volume)
            iroh.start(
                displayName: restoredProfile?.name ?? "Caller",
                avatarImage: restoredProfile?.usesDefaultAvatar == false ? restoredProfile?.avatar : nil,
                usesDefaultAvatar: restoredProfile?.usesDefaultAvatar ?? true
            )
        }
        .onChange(of: volume) { _, newValue in
            iroh.setOutputVolume(newValue)
        }
        .onDisappear {
            networkPumpTask?.cancel()
            iroh.stop()
        }
    }

    /// The complete interface below the modal glass/sheet. Keeping this in a
    /// single compositing subtree means the 25 pt sheet-open blur is applied
    /// consistently to the header, avatar dial, status, volume and VU panels.
    private var mainInterface: some View {
        ZStack(alignment: .topLeading) {
            // The actual Window/Glass surface now lives in AppKit beneath
            // this SwiftUI hierarchy: NSVisualEffectView (.behindWindow) plus
            // the Figma #ABABAB @ 60% tint. Keeping the SwiftUI root clear is
            // essential; an opaque or tinted SwiftUI backing would cover the
            // native backdrop sampling we are trying to expose.

            // Transparent AppKit hit surface for otherwise-empty areas.
            // Interactive controls sit above it and retain their own gestures.
            DraggableWindowArea()
                .frame(width: 320, height: 672)

            // Exact Figma frame geometry: 320 × 672, using the 8-point grid.
            topBar
                .frame(width: 272, height: 24)
                .offset(x: 24, y: 24)

            radioArea
                .frame(width: 272, height: 272)
                .offset(x: 24, y: 96)

            statusPanel
                .frame(width: 272, height: 48)
                .offset(x: 24, y: 408)

            volumePanel
                .frame(width: 272, height: 80)
                .offset(x: 24, y: 472)

            vuPanel
                .frame(width: 272, height: 80)
                .offset(x: 24, y: 568)
        }
        .frame(width: 320, height: 672)
    }



    private func openProfile() {
        if hasProfile {
            draftProfileName = savedProfileName
            draftProfileAvatar = savedProfileAvatar
            draftProfileAvatarToken = savedProfileAvatarToken
        } else {
            draftProfileName = ""
            draftProfileAvatar = nil
            draftProfileAvatarToken = ""
        }

        showProfile = true
    }

    private func commitProfile() {
        let trimmedName = draftProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? nextCallerName() : trimmedName

        let resolvedAvatar = draftProfileAvatar ?? defaultAvatarImage()
        let resolvedToken = draftProfileAvatarToken.isEmpty ? "default-buddha" : draftProfileAvatarToken

        savedProfileName = resolvedName
        savedProfileAvatar = resolvedAvatar
        savedProfileAvatarToken = resolvedToken
        hasProfile = true

        persistProfile(
            name: resolvedName,
            avatar: resolvedAvatar,
            avatarToken: resolvedToken
        )

        // Reflect the saved local profile at 12 o'clock and publish the same
        // profile to every connected peer. Default Buddha avatars are signalled
        // by token rather than repeatedly transmitting identical image bytes.
        currentUserAvatar = resolvedAvatar
        iroh.updateProfile(
            name: resolvedName,
            avatarImage: resolvedToken == "default-buddha" ? nil : resolvedAvatar,
            usesDefaultAvatar: resolvedToken == "default-buddha"
        )

        showProfile = false
    }

    private func nextCallerName() -> String {
        let usedNumbers = Set(
            iroh.remoteSlots.compactMap { $0 }.compactMap { participant -> Int? in
                let prefix = "Caller "
                guard participant.name.hasPrefix(prefix) else { return nil }
                return Int(participant.name.dropFirst(prefix.count))
            }
        )

        let number = (1...7).first(where: { !usedNumbers.contains($0) }) ?? 7
        return "Caller \(number)"
    }

    private func defaultAvatarImage() -> NSImage? {
        NSImage(named: NSImage.Name("ToyBuddha"))
    }

    private struct RestoredProfile {
        let name: String
        let avatar: NSImage?
        let avatarToken: String
        let usesDefaultAvatar: Bool
    }

    private enum ProfileStorage {
        static let nameKey = "LandlineProfileName"
        static let avatarTokenKey = "LandlineProfileAvatarToken"
        static let customAvatarFilename = "profile-avatar.jpg"
    }

    /// Restores the profile from the app's persistent sandbox. Custom avatar
    /// bytes live in Application Support rather than UserDefaults, while the
    /// small name/token metadata remains in UserDefaults.
    @MainActor
    private func restorePersistedProfile() -> RestoredProfile? {
        let defaults = UserDefaults.standard
        guard let storedName = defaults.string(forKey: ProfileStorage.nameKey),
              !storedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let storedToken = defaults.string(forKey: ProfileStorage.avatarTokenKey) ?? "default-buddha"
        let usesDefaultAvatar = storedToken == "default-buddha"
        var avatar = defaultAvatarImage()
        var resolvedToken = storedToken
        var resolvedUsesDefault = usesDefaultAvatar

        if !usesDefaultAvatar {
            if let url = persistentAvatarURL(),
               let data = try? Data(contentsOf: url),
               let storedImage = NSImage(data: data) {
                avatar = storedImage
            } else {
                // If the cached custom image was removed independently, fall
                // back cleanly to the default rather than showing a blank slot.
                avatar = defaultAvatarImage()
                resolvedToken = "default-buddha"
                resolvedUsesDefault = true
                defaults.set(resolvedToken, forKey: ProfileStorage.avatarTokenKey)
            }
        }

        hasProfile = true
        savedProfileName = storedName
        savedProfileAvatar = avatar
        savedProfileAvatarToken = resolvedToken
        draftProfileName = storedName
        draftProfileAvatar = avatar
        draftProfileAvatarToken = resolvedToken
        currentUserAvatar = avatar

        return RestoredProfile(
            name: storedName,
            avatar: avatar,
            avatarToken: resolvedToken,
            usesDefaultAvatar: resolvedUsesDefault
        )
    }

    @MainActor
    private func persistProfile(name: String, avatar: NSImage?, avatarToken: String) {
        let defaults = UserDefaults.standard
        defaults.set(name, forKey: ProfileStorage.nameKey)
        defaults.set(avatarToken, forKey: ProfileStorage.avatarTokenKey)

        guard let url = persistentAvatarURL() else { return }

        if avatarToken == "default-buddha" {
            try? FileManager.default.removeItem(at: url)
            return
        }

        guard let avatar, let jpegData = persistentAvatarJPEGData(from: avatar) else { return }
        try? jpegData.write(to: url, options: .atomic)
    }

    private func persistentAvatarURL() -> URL? {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }

        let directory = applicationSupport.appendingPathComponent("Landline", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(ProfileStorage.customAvatarFilename)
        } catch {
            NSLog("Landline profile storage unavailable: %@", error.localizedDescription)
            return nil
        }
    }

    /// Persist a centre-cropped 512 px JPEG. This is larger than the 48 pt dial
    /// rendering but avoids retaining arbitrary multi-megabyte source photos.
    @MainActor
    private func persistentAvatarJPEGData(from image: NSImage) -> Data? {
        let target = NSSize(width: 512, height: 512)
        let source = image.size
        guard source.width > 0, source.height > 0 else { return nil }

        let scale = max(target.width / source.width, target.height / source.height)
        let drawSize = NSSize(width: source.width * scale, height: source.height * scale)
        let origin = NSPoint(
            x: (target.width - drawSize.width) / 2,
            y: (target.height - drawSize.height) / 2
        )

        let rendered = NSImage(size: target)
        rendered.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: origin, size: drawSize),
            from: NSRect(origin: .zero, size: source),
            operation: .copy,
            fraction: 1
        )
        rendered.unlockFocus()

        guard let tiff = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }

        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.88]
        )
    }

    private var localNetworkDisplayName: String {
        if hasProfile, !savedProfileName.isEmpty {
            return savedProfileName
        }
        return "Caller"
    }

    private var topBar: some View {
        // Exact Figma geometry:
        // traffic backing 64 × 24 @ x=24
        // Landline badge 152 × 24 @ x=104
        // profile control 24 × 24 @ x=272
        // which gives 16 pt gaps between the three controls.
        HStack(spacing: Grid.x2) {
            // The actual AppKit traffic lights remain in their native title-bar
            // hierarchy and are positioned by AppDelegate. SwiftUI draws only
            // the 64 × 24 Figma backing plate, so there is no competing hit box.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.20))
                .frame(width: 64, height: 24)
                .allowsHitTesting(false)

            RadioDisplay()
                .frame(width: 152, height: 24)

            Button {
                openProfile()
            } label: {
                BundledImage(name: "profile_icon", extension: "png")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .scaleEffect(hoveredProfile ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hoveredProfile)
            .onHover { hoveredProfile = $0 }
        }
        .frame(width: 272, height: 24, alignment: .leading)
    }

    private var radioArea: some View {
        ZStack {
            Circle()
                .fill(LandlineColor.panel)
                .frame(width: 272, height: 272)

            // Eight fixed positions. Position 0 is always this Mac; remote
            // participants occupy positions 1...7 clockwise in the first free
            // slot assigned by IrohClient. Empty positions remain black.
            ForEach(0..<8, id: \.self) { index in
                if index == 0 {
                    ContactAvatar(
                        contact: Contact(
                            name: localNetworkDisplayName,
                            avatarAsset: "",
                            isOnline: true,
                            isTalking: false
                        ),
                        suppressTalking: false,
                        forceTalking: isTalking,
                        overrideImage: currentUserAvatar ?? defaultAvatarImage()
                    )
                    .offset(avatarOffset(index: index, count: 8, radius: 88))
                } else if let participant = iroh.remoteSlots[index - 1] {
                    ContactAvatar(
                        contact: Contact(
                            name: participant.name,
                            avatarAsset: "",
                            isOnline: true,
                            isTalking: false
                        ),
                        suppressTalking: isTalking,
                        forceTalking: !isTalking && iroh.remoteSpeakerID == participant.id,
                        overrideImage: remoteAvatarImage(for: participant)
                    )
                    .contentShape(Circle())
                    .onHover { hovering in
                        if hovering {
                            hoveredRemoteParticipantID = participant.id
                        } else if hoveredRemoteParticipantID == participant.id {
                            hoveredRemoteParticipantID = nil
                        }
                    }
                    .offset(avatarOffset(index: index, count: 8, radius: 88))
                } else {
                    ContactAvatar(
                        contact: Contact(
                            name: "",
                            avatarAsset: "",
                            isOnline: false,
                            isTalking: false
                        ),
                        suppressTalking: true,
                        forceTalking: false,
                        overrideImage: nil
                    )
                    .offset(avatarOffset(index: index, count: 8, radius: 88))
                }
            }

            PushToTalkButton(
                state: micState,
                isHovered: hoveredPTT,
                onHover: { hoveredPTT = $0 },
                onPressChanged: handlePTTPress
            )
        }
        .frame(width: 272, height: 272)
    }

    private func remoteAvatarImage(for participant: RemoteParticipant) -> NSImage? {
        if participant.usesDefaultAvatar {
            return defaultAvatarImage()
        }
        if let avatarData = participant.avatarData, let image = NSImage(data: avatarData) {
            return image
        }
        return defaultAvatarImage()
    }

    private var statusPanel: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LandlineColor.panel)

            // Figma geometry is exact here: 18 × 18 at x=11, y=15.
            // The status glyph is kept native for this pass; PTT artwork below
            // uses the exact supplied Figma vectors.
            Image(systemName: statusSystemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 217/255, green: 217/255, blue: 217/255))
                .frame(width: 18, height: 18)
                .offset(x: 11, y: 15)

            Text(statusText)
                .font(.custom("Inter", size: 10).weight(.medium))
                .foregroundStyle(Color(red: 217/255, green: 217/255, blue: 217/255))
                .lineLimit(1)
                .frame(width: 216, height: 48, alignment: .leading)
                .offset(x: 37, y: 0)
        }
        .frame(width: 272, height: 48)
    }

    private var hoveredRemoteParticipant: RemoteParticipant? {
        guard let hoveredRemoteParticipantID else { return nil }
        return iroh.remoteSlots.compactMap { $0 }.first { $0.id == hoveredRemoteParticipantID }
    }

    private var statusSystemImage: String {
        if isTalking { return "mic.fill" }
        if iroh.remoteSpeakerName != nil { return "speaker.wave.2.fill" }
        if hoveredRemoteParticipant != nil { return "person.fill" }
        return "speaker.slash.fill"
    }

    private var statusText: String {
        if let errorMessage = microphone.errorMessage {
            return errorMessage
        }
        if isTalking { return "You are talking" }
        if let remoteSpeakerName = iroh.remoteSpeakerName {
            return "\(remoteSpeakerName) is talking"
        }
        if let hoveredRemoteParticipant {
            return "\(hoveredRemoteParticipant.name) is online"
        }
        if isMuted {
            return hoveredPTT ? "Click to talk" : "You are muted"
        }
        return "You are muted"
    }

    private var volumePanel: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LandlineColor.panel)

            Text("Volume")
                .font(.custom("Inter Tight", size: 13).weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 71, height: 34, alignment: .leading)
                .offset(x: 25, y: 2)

            Text("\(Int(volume * 100))")
                .font(.custom("Inter Tight", size: 13).weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: 71, height: 24, alignment: .trailing)
                .offset(x: 177, y: 7)

            VolumeSlider(value: $volume)
                .frame(width: 225, height: 24)
                .offset(x: 23, y: 32)
        }
        .frame(width: 272, height: 80)
    }

    private var vuPanel: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(0..<16, id: \.self) { index in
                let threshold = Double(index + 1) / 16.0
                Capsule(style: .continuous)
                    .fill(threshold <= microphone.level ? vuActiveColor(for: index) : LandlineColor.inactive)
                    .frame(width: 8, height: 56)
            }
        }
        .frame(width: 248, height: 56)
        .frame(width: 272, height: 80, alignment: .center)
        .background(LandlineColor.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Matches the WT Max VU frame in Figma: ten normal-level segments,
    /// three high-level warning segments and three near-clipping segments.
    private func vuActiveColor(for index: Int) -> Color {
        switch index {
        case 0...9:
            return LandlineColor.vuGreen
        case 10...12:
            return LandlineColor.vuOrange
        default:
            return LandlineColor.vuRed
        }
    }

    private func avatarOffset(index: Int, count: Int, radius: CGFloat) -> CGSize {
        let angle = (CGFloat(index) / CGFloat(count)) * 2 * .pi - .pi / 2
        return CGSize(width: CoreGraphics.cos(angle) * radius, height: CoreGraphics.sin(angle) * radius)
    }

    @MainActor
    private func handlePTTPress(_ down: Bool) {
        guard down != pttHeld else { return }
        pttHeld = down

        if down {
            micState = .talking
            pttCaptureTask?.cancel()
            pttCaptureTask = Task { @MainActor in
                let started = await microphone.beginCapture()

                // Permission prompts are asynchronous. If the user released PTT
                // while macOS was asking, do not begin a late capture session.
                guard !Task.isCancelled, pttHeld else {
                    if started { microphone.stopCapture() }
                    return
                }

                if started {
                    let granted = await iroh.beginTransmit()
                    if granted {
                        startNetworkAudioPump()
                    } else {
                        microphone.stopCapture()
                        micState = .muted
                        pttHeld = false
                    }
                } else {
                    micState = .muted
                    pttHeld = false
                }
            }
        } else {
            pttCaptureTask?.cancel()
            pttCaptureTask = nil
            networkPumpTask?.cancel()
            networkPumpTask = nil
            iroh.endTransmit()
            microphone.stopCapture()
            micState = .muted
        }
    }

    @MainActor
    private func startNetworkAudioPump() {
        networkPumpTask?.cancel()
        networkPumpTask = Task { @MainActor in
            while !Task.isCancelled, pttHeld {
                let frames = microphone.drainNetworkFrames()
                for frame in frames {
                    guard !Task.isCancelled, pttHeld else { break }
                    await iroh.sendAudioFrame(frame)
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }
}


private struct RadioDisplay: View {
    var body: some View {
        // Exact vector title-bar artwork from the Figma design: speaker glyphs,
        // meter lines and LANDLINE wordmark are kept as one supplied 152 × 24 vector asset.
        // It is bundled as vector PDF so AppKit renders it crisply at Retina scale.
        BundledImage(name: "landline_title", extension: "pdf")
            .frame(width: 152, height: 24)
    }
}

private struct BundledImage: View {
    let name: String
    let `extension`: String

    private var image: NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: `extension`) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
    }
}

private struct ContactAvatar: View {
    let contact: Contact
    let suppressTalking: Bool
    let forceTalking: Bool
    let overrideImage: NSImage?

    private var bundledAvatar: NSImage? {
        if let overrideImage {
            return overrideImage
        }

        guard !contact.avatarAsset.isEmpty,
              let url = Bundle.main.url(forResource: contact.avatarAsset, withExtension: "png")
        else { return nil }

        return NSImage(contentsOf: url)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(contact.isOnline ? Color(red: 0.25, green: 0.30, blue: 0.31) : Color.black)
                .frame(width: 48, height: 48)
                .overlay {
                    if let image = bundledAvatar {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .opacity(contact.isOnline ? 1.0 : 0.33)
                    }
                }

            // While the local user is holding PTT, show the speaking badge on
            // the 12 o'clock avatar. Remote speaking badges are suppressed for
            // the duration so there is only one active-speaker indicator.
            if forceTalking || (contact.isTalking && !suppressTalking) {
                TalkingBadge()
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: 48, height: 48)
    }
}

private struct TalkingBadge: View {
    @State private var phase = false

    private let firstHeights: [CGFloat] = [7, 13, 10, 6]
    private let secondHeights: [CGFloat] = [12, 7, 14, 9]

    var body: some View {
        ZStack {
            Circle().fill(LandlineColor.green)

            // Four 2 pt bars plus three 2 pt gaps = 14 pt exactly. Keeping
            // this inner group at a fixed 14 × 16 frame makes its geometric
            // centre coincide with the 24 × 24 badge centre at every phase.
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.80))
                        .frame(width: 2, height: phase ? firstHeights[index] : secondHeights[index])
                }
            }
            .frame(width: 14, height: 16, alignment: .center)
        }
        .frame(width: 24, height: 24)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                phase.toggle()
            }
        }
    }
}

private struct PushToTalkButton: View {
    let state: MicState
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onPressChanged: (Bool) -> Void

    @GestureState private var pressed = false

    var body: some View {
        let muted = state == .muted
        let talking = state == .talking

        Circle()
            .fill(muted ? LandlineColor.red : LandlineColor.green)
            .frame(width: 80, height: 80)
            .overlay {
                // Original filled PTT artwork exported from Figma.
                BundledImage(name: muted ? "mic_muted" : "mic_on", extension: "pdf")
                    .frame(width: 24, height: 24)
            }
            .scaleEffect((isHovered || pressed || talking) ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.10), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(Circle())
            .onHover(perform: onHover)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, value, _ in value = true }
                    .onChanged { _ in onPressChanged(true) }
                    .onEnded { _ in onPressChanged(false) }
            )
    }
}

private struct VolumeSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { _ in
            let knob: CGFloat = 24
            let trackX: CGFloat = 1
            let trackWidth: CGFloat = 224
            let travel: CGFloat = 201
            let knobX = travel * value
            let fillWidth = min(trackWidth, max(0, knobX + knob / 2 - trackX))

            ZStack(alignment: .topLeading) {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color(red: 50/255, green: 50/255, blue: 50/255), lineWidth: 0.5)
                    }
                    .frame(width: trackWidth, height: 8)
                    .offset(x: trackX, y: 8)

                Capsule(style: .continuous)
                    .fill(LandlineColor.green)
                    .frame(width: fillWidth, height: 8)
                    .offset(x: trackX, y: 8)

                Circle()
                    .fill(.white)
                    .overlay {
                        Circle()
                            .fill(LandlineColor.green)
                            .frame(width: 12, height: 12)
                    }
                    .frame(width: knob, height: knob)
                    .offset(x: knobX, y: 0)
            }
            .frame(width: 225, height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let raw = (drag.location.x - knob / 2) / travel
                        value = min(1, max(0, raw))
                    }
            )
        }
    }
}

private struct ProfileSheet: View {
    let hasProfile: Bool
    let savedName: String
    let savedAvatarToken: String
    @Binding var name: String
    @Binding var avatarImage: NSImage?
    @Binding var avatarToken: String
    let onCommit: () -> Void
    let onClose: () -> Void

    @State private var closeHovered = false

    private enum Mode: Equatable {
        case defaultCreate
        case customCreate
        case profile
    }

    private var mode: Mode {
        if hasProfile {
            return .profile
        }

        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = !avatarToken.isEmpty
        return (hasName || hasImage) ? .customCreate : .defaultCreate
    }

    private var profileHasChanges: Bool {
        name != savedName || avatarToken != savedAvatarToken
    }

    private var buttonTitle: String {
        switch mode {
        case .defaultCreate: return "Skip"
        case .customCreate: return "Apply"
        case .profile: return "Update"
        }
    }

    private var headline: String {
        mode == .profile ? "Edit profile" : "Create a profile"
    }

    private var buttonEnabled: Bool {
        mode != .profile || profileHasChanges
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.95))

            Text(headline)
                .font(.custom("Inter Tight", size: 24).weight(.semibold))
                .foregroundStyle(Color(red: 23/255, green: 23/255, blue: 23/255))
                .frame(width: 272, height: 80, alignment: .bottomLeading)
                .offset(x: 24, y: 0)

            Button(action: onClose) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(closeHovered ? Color(red: 243/255, green: 243/255, blue: 243/255) : .clear)

                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 23/255, green: 23/255, blue: 23/255))
                }
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 280, y: 8)
            .onHover { closeHovered = $0 }

            Text("Name")
                .font(.custom("Inter Tight", size: 14).weight(.medium))
                .foregroundStyle(Color(red: 23/255, green: 23/255, blue: 23/255))
                .frame(width: 272, height: 17, alignment: .leading)
                .offset(x: 24, y: 106)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 243/255, green: 243/255, blue: 243/255))

                TextField(
                    "",
                    text: $name,
                    prompt: Text("Random Caller")
                        .foregroundStyle(Color(red: 217/255, green: 217/255, blue: 217/255))
                )
                .textFieldStyle(.plain)
                .font(.custom("Inter Tight", size: 16).weight(.medium))
                .foregroundStyle(Color(red: 23/255, green: 23/255, blue: 23/255))
                .padding(.horizontal, 16)
            }
            .frame(width: 272, height: 48)
            .offset(x: 24, y: 128)

            Text("Avatar")
                .font(.custom("Inter Tight", size: 14).weight(.medium))
                .foregroundStyle(Color(red: 23/255, green: 23/255, blue: 23/255))
                .frame(width: 131, height: 17, alignment: .leading)
                .offset(x: 24, y: 210)

            avatarUploadArea
                .frame(width: 272, height: 208)
                .offset(x: 24, y: 232)

            Text("Click to upload or drop an image to customise")
                .font(.custom("Inter Tight", size: 12).weight(.medium))
                .foregroundStyle(Color(red: 107/255, green: 107/255, blue: 107/255))
                .multilineTextAlignment(.center)
                .frame(width: 320, height: 72, alignment: .center)
                .offset(x: 0, y: 440)

            Button(action: {
                guard buttonEnabled else { return }
                onCommit()
            }) {
                Text(buttonTitle)
                    .font(.custom("Inter Tight", size: 14).weight(.semibold))
                    // Do not use SwiftUI's .disabled modifier here: it applies
                    // an inherited disabled appearance to the whole label tree.
                    // Keep "Update" readable while only the button surface fades.
                    .foregroundStyle(
                        buttonEnabled
                            ? Color(red: 235/255, green: 235/255, blue: 235/255)
                            : Color(red: 107/255, green: 107/255, blue: 107/255)
                    )
                    .frame(width: 272, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                Color(red: 23/255, green: 23/255, blue: 23/255)
                                    .opacity(buttonEnabled ? 1.0 : 0.20)
                            )
                    )
            }
            .buttonStyle(.plain)
            .allowsHitTesting(buttonEnabled)
            .accessibilityRespondsToUserInteraction(buttonEnabled)
            .offset(x: 24, y: 512)
        }
        .frame(width: 320, height: 584)
    }

    private var avatarUploadArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 243/255, green: 243/255, blue: 243/255))

            if let avatarImage {
                Image(nsImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 144, height: 144)
                    .clipShape(Circle())
            } else {
                Image("ToyBuddha")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 144, height: 144)
                    .clipShape(Circle())
                    .opacity(0.10)

                ZStack {
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(
                            Color(red: 205/255, green: 209/255, blue: 205/255),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                        .frame(width: 18, height: 18)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(red: 23/255, green: 23/255, blue: 23/255).opacity(0.72))
                }
                .frame(width: 24, height: 24)
            }

            AvatarFileDropView(
                onClick: choosePhoto,
                onFileDrop: loadDroppedImage
            )
            .frame(width: 272, height: 208)
        }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let url = panel.url
        else { return }

        loadImage(from: url)
    }

    private func loadDroppedImage(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg"].contains(ext) else { return }
        loadImage(from: url)
    }

    private func loadImage(from url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        avatarImage = image
        avatarToken = UUID().uuidString
    }
}

/// Native drag/drop target for the Figma avatar upload region. Keeping file
/// drop handling in AppKit avoids introducing a window-wide SwiftUI drop
/// overlay that could intercept PTT or slider gestures.
private struct AvatarFileDropView: NSViewRepresentable {
    let onClick: () -> Void
    let onFileDrop: (URL) -> Void

    func makeNSView(context: Context) -> AvatarFileDropNSView {
        AvatarFileDropNSView(onClick: onClick, onFileDrop: onFileDrop)
    }

    func updateNSView(_ nsView: AvatarFileDropNSView, context: Context) {
        nsView.onClick = onClick
        nsView.onFileDrop = onFileDrop
    }
}

private final class AvatarFileDropNSView: NSView {
    var onClick: () -> Void
    var onFileDrop: (URL) -> Void

    init(onClick: @escaping () -> Void, onFileDrop: @escaping (URL) -> Void) {
        self.onClick = onClick
        self.onFileDrop = onFileDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptableFileURL(from: sender) == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptableFileURL(from: sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = acceptableFileURL(from: sender) else { return false }
        onFileDrop(url)
        return true
    }

    private func acceptableFileURL(from sender: NSDraggingInfo) -> URL? {
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL],
        let nsURL = urls.first
        else { return nil }

        let url = nsURL as URL
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg"].contains(ext) ? url : nil
    }
}

private struct DraggableWindowArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableBackgroundView {
        DraggableBackgroundView(frame: .zero)
    }

    func updateNSView(_ nsView: DraggableBackgroundView, context: Context) {}
}

private final class DraggableBackgroundView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
