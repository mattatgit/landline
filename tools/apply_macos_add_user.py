from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)

content_path = Path("LandlineMac/ContentView.swift")
iroh_path = Path("LandlineMac/IrohClient.swift")

content = content_path.read_text()

content = replace_once(
    content,
    '''    @State private var hoveredProfile = false\n    @State private var hoveredRemoteParticipantID: String?\n    @State private var showProfile = false\n''',
    '''    @State private var hoveredProfile = false\n    @State private var hoveredRemoteParticipantID: String?\n    @State private var hoveredEmptySlotIndex: Int?\n    @State private var showProfile = false\n    @State private var showAddUser = false\n    @State private var selectedAddSlotIndex: Int?\n    @State private var addUserID = ""\n    @State private var copiedLandlineID = false\n    @State private var addUserFeedbackTask: Task<Void, Never>?\n''',
    "ContentView state",
)

content = replace_once(
    content,
    '''    private var isMuted: Bool { micState == .muted }\n    private var isTalking: Bool { micState == .talking }\n''',
    '''    private var isMuted: Bool { micState == .muted }\n    private var isTalking: Bool { micState == .talking }\n    private var isModalPresented: Bool { showProfile || showAddUser }\n\n    private var modalVeilOpacity: Double {\n        if showProfile { return 0.10 }\n        if showAddUser { return 0.06 }\n        return 0\n    }\n''',
    "ContentView modal state",
)

content = replace_once(
    content,
    '''            mainInterface\n                .blur(radius: showProfile ? 25 : 0)\n                .animation(.easeOut(duration: 0.28), value: showProfile)\n''',
    '''            mainInterface\n                .blur(radius: isModalPresented ? 25 : 0)\n                .animation(.easeOut(duration: 0.28), value: showProfile)\n                .animation(.easeOut(duration: 0.10), value: showAddUser)\n''',
    "ContentView main blur",
)

content = replace_once(
    content,
    '''            Color(red: 248/255, green: 248/255, blue: 248/255)\n                .opacity(showProfile ? 0.10 : 0)\n                .frame(width: 320, height: 672)\n                .contentShape(Rectangle())\n                .allowsHitTesting(showProfile)\n                .onTapGesture {\n                    showProfile = false\n                }\n                .animation(.easeOut(duration: 0.28), value: showProfile)\n                .zIndex(20)\n''',
    '''            Color(red: 248/255, green: 248/255, blue: 248/255)\n                .opacity(modalVeilOpacity)\n                .frame(width: 320, height: 672)\n                .contentShape(Rectangle())\n                .allowsHitTesting(isModalPresented)\n                .onTapGesture {\n                    closePresentedSheet()\n                }\n                .animation(.easeOut(duration: 0.28), value: showProfile)\n                .animation(.easeOut(duration: 0.10), value: showAddUser)\n                .zIndex(20)\n''',
    "ContentView modal veil",
)

content = replace_once(
    content,
    '''            .allowsHitTesting(showProfile)\n            .animation(.easeOut(duration: 0.28), value: showProfile)\n            .zIndex(21)\n        }\n''',
    '''            .allowsHitTesting(showProfile)\n            .animation(.easeOut(duration: 0.28), value: showProfile)\n            .zIndex(21)\n\n            AddUserSheet(\n                isPresented: showAddUser,\n                landlineID: iroh.endpointId,\n                enteredID: $addUserID,\n                copied: copiedLandlineID,\n                onSubmit: submitAddUser,\n                onCopy: copyLandlineID,\n                onClose: closeAddUser\n            )\n            .frame(width: 320, height: 472)\n            .offset(x: 0, y: showAddUser ? 200 : 680)\n            .allowsHitTesting(showAddUser)\n            .animation(.easeOut(duration: 0.10), value: showAddUser)\n            .zIndex(22)\n        }\n''',
    "ContentView AddUser sheet mount",
)

content = replace_once(
    content,
    '''        .onDisappear {\n            networkPumpTask?.cancel()\n            iroh.stop()\n        }\n''',
    '''        .onDisappear {\n            networkPumpTask?.cancel()\n            addUserFeedbackTask?.cancel()\n            iroh.stop()\n        }\n''',
    "ContentView disappear cleanup",
)

content = replace_once(
    content,
    '''\n\n\n    private func openProfile() {\n''',
    '''\n\n\n    private func closePresentedSheet() {\n        if showAddUser {\n            closeAddUser()\n        } else {\n            showProfile = false\n        }\n    }\n\n    private func openAddUser(remoteSlotIndex: Int) {\n        guard iroh.remoteSlots.indices.contains(remoteSlotIndex),\n              iroh.remoteSlots[remoteSlotIndex] == nil\n        else { return }\n\n        showProfile = false\n        addUserFeedbackTask?.cancel()\n        addUserFeedbackTask = nil\n        selectedAddSlotIndex = remoteSlotIndex\n        addUserID = ""\n        copiedLandlineID = false\n        hoveredEmptySlotIndex = nil\n        showAddUser = true\n    }\n\n    private func closeAddUser() {\n        addUserFeedbackTask?.cancel()\n        addUserFeedbackTask = nil\n        selectedAddSlotIndex = nil\n        addUserID = ""\n        copiedLandlineID = false\n        showAddUser = false\n    }\n\n    private func submitAddUser() {\n        let trimmedID = addUserID.trimmingCharacters(in: .whitespacesAndNewlines)\n        guard let selectedAddSlotIndex, !trimmedID.isEmpty else { return }\n\n        iroh.connect(to: trimmedID, preferredSlotIndex: selectedAddSlotIndex)\n        closeAddUser()\n    }\n\n    private func copyLandlineID() {\n        let id = iroh.endpointId.trimmingCharacters(in: .whitespacesAndNewlines)\n        guard !id.isEmpty else { return }\n\n        let pasteboard = NSPasteboard.general\n        pasteboard.clearContents()\n        pasteboard.setString(id, forType: .string)\n\n        copiedLandlineID = true\n        addUserFeedbackTask?.cancel()\n        addUserFeedbackTask = Task { @MainActor in\n            try? await Task.sleep(for: .milliseconds(650))\n            guard !Task.isCancelled else { return }\n            selectedAddSlotIndex = nil\n            addUserID = ""\n            copiedLandlineID = false\n            showAddUser = false\n            addUserFeedbackTask = nil\n        }\n    }\n\n    private func openProfile() {\n        closeAddUser()\n''',
    "ContentView AddUser actions",
)

content = replace_once(
    content,
    '''                } else {\n                    ContactAvatar(\n                        contact: Contact(\n                            name: "",\n                            avatarAsset: "",\n                            isOnline: false,\n                            isTalking: false\n                        ),\n                        suppressTalking: true,\n                        forceTalking: false,\n                        overrideImage: nil\n                    )\n                    .offset(avatarOffset(index: index, count: 8, radius: 88))\n                }\n''',
    '''                } else {\n                    let remoteSlotIndex = index - 1\n                    EmptyAddSlot(\n                        isHovered: hoveredEmptySlotIndex == remoteSlotIndex,\n                        onHover: { hovering in\n                            if hovering {\n                                hoveredEmptySlotIndex = remoteSlotIndex\n                            } else if hoveredEmptySlotIndex == remoteSlotIndex {\n                                hoveredEmptySlotIndex = nil\n                            }\n                        },\n                        onTap: {\n                            openAddUser(remoteSlotIndex: remoteSlotIndex)\n                        }\n                    )\n                    .offset(avatarOffset(index: index, count: 8, radius: 88))\n                }\n''',
    "ContentView empty dial slots",
)

content = replace_once(
    content,
    '''            // Figma geometry is exact here: 18 × 18 at x=11, y=15.\n            // The status glyph is kept native for this pass; PTT artwork below\n            // uses the exact supplied Figma vectors.\n            Image(systemName: statusSystemImage)\n                .font(.system(size: 14, weight: .medium))\n                .foregroundStyle(Color(red: 217/255, green: 217/255, blue: 217/255))\n                .frame(width: 18, height: 18)\n                .offset(x: 11, y: 15)\n\n            Text(statusText)\n                .font(.custom("Inter", size: 10).weight(.medium))\n                .foregroundStyle(Color(red: 217/255, green: 217/255, blue: 217/255))\n                .lineLimit(1)\n                .frame(width: 216, height: 48, alignment: .leading)\n                .offset(x: 37, y: 0)\n''',
    '''            if hoveredEmptySlotIndex != nil {\n                HStack(spacing: 4) {\n                    AddUserStatusIcon()\n                        .frame(width: 24, height: 24)\n\n                    Text("Add someone to Landline")\n                        .font(.custom("Inter", size: 10).weight(.medium))\n                        .foregroundStyle(Color(red: 217/255, green: 217/255, blue: 217/255))\n                        .lineLimit(1)\n                }\n                .frame(width: 254, height: 48, alignment: .leading)\n                .offset(x: 9, y: 0)\n            } else {\n                // Figma geometry is exact here: 18 × 18 at x=11, y=15.\n                // The status glyph is kept native for the established PTT states.\n                Image(systemName: statusSystemImage)\n                    .font(.system(size: 14, weight: .medium))\n                    .foregroundStyle(Color(red: 217/255, green: 217/255, blue: 217/255))\n                    .frame(width: 18, height: 18)\n                    .offset(x: 11, y: 15)\n\n                Text(statusText)\n                    .font(.custom("Inter", size: 10).weight(.medium))\n                    .foregroundStyle(Color(red: 217/255, green: 217/255, blue: 217/255))\n                    .lineLimit(1)\n                    .frame(width: 216, height: 48, alignment: .leading)\n                    .offset(x: 37, y: 0)\n            }\n''',
    "ContentView AddUser status",
)

insert_marker = '''\n\nprivate struct RadioDisplay: View {\n'''
add_user_views = r'''\n\nprivate struct EmptyAddSlot: View {\n    let isHovered: Bool\n    let onHover: (Bool) -> Void\n    let onTap: () -> Void\n\n    var body: some View {\n        Button(action: onTap) {\n            ZStack {\n                Circle()\n                    .fill(Color(red: 11/255, green: 11/255, blue: 11/255))\n                    .frame(width: 56, height: 56)\n\n                ZStack {\n                    Capsule(style: .continuous)\n                        .fill(Color(red: 50/255, green: 50/255, blue: 50/255))\n                        .frame(width: 3, height: 18)\n\n                    Capsule(style: .continuous)\n                        .fill(Color(red: 50/255, green: 50/255, blue: 50/255))\n                        .frame(width: 18, height: 3)\n                }\n                .opacity(isHovered ? 1 : 0)\n            }\n            .frame(width: 56, height: 56)\n            .scaleEffect(isHovered ? 1.0 : 48.0 / 56.0)\n            .animation(.easeOut(duration: 0.10), value: isHovered)\n            .contentShape(Circle())\n        }\n        .buttonStyle(.plain)\n        .frame(width: 56, height: 56)\n        .contentShape(Circle())\n        .onHover(perform: onHover)\n        .accessibilityLabel("Add someone to Landline")\n    }\n}\n\nprivate struct AddUserStatusIcon: View {\n    var body: some View {\n        Canvas { context, _ in\n            let strokeColor = Color(red: 217/255, green: 217/255, blue: 217/255)\n            let strokeStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)\n\n            var path = Path()\n            path.addEllipse(in: CGRect(x: 11.5, y: 11.5, width: 8, height: 8))\n            path.move(to: CGPoint(x: 15.5, y: 13.5))\n            path.addLine(to: CGPoint(x: 15.5, y: 17.5))\n            path.move(to: CGPoint(x: 13.5, y: 15.5))\n            path.addLine(to: CGPoint(x: 17.5, y: 15.5))\n\n            path.move(to: CGPoint(x: 4.5, y: 15.4999))\n            path.addCurve(\n                to: CGPoint(x: 5.03804, y: 13.3687),\n                control1: CGPoint(x: 4.50051, y: 14.7560),\n                control2: CGPoint(x: 4.68536, y: 14.0238)\n            )\n            path.addCurve(\n                to: CGPoint(x: 6.52099, y: 11.7463),\n                control1: CGPoint(x: 5.39071, y: 12.7137),\n                control2: CGPoint(x: 5.90022, y: 12.1563)\n            )\n            path.addCurve(\n                to: CGPoint(x: 8.59536, y: 11.0194),\n                control1: CGPoint(x: 7.14177, y: 11.3363),\n                control2: CGPoint(x: 7.85447, y: 11.0866)\n            )\n            path.addCurve(\n                to: CGPoint(x: 10.7667, y: 11.3612),\n                control1: CGPoint(x: 9.33626, y: 10.9522),\n                control2: CGPoint(x: 10.0823, y: 11.0696)\n            )\n            path.addEllipse(in: CGRect(x: 6.25, y: 4.5, width: 5.5, height: 5.5))\n\n            context.stroke(path, with: .color(strokeColor), style: strokeStyle)\n        }\n        .frame(width: 24, height: 24)\n        .allowsHitTesting(false)\n    }\n}\n\nprivate struct AddUserSheet: View {\n    let isPresented: Bool\n    let landlineID: String\n    @Binding var enteredID: String\n    let copied: Bool\n    let onSubmit: () -> Void\n    let onCopy: () -> Void\n    let onClose: () -> Void\n\n    @State private var closeHovered = false\n    @FocusState private var inputFocused: Bool\n\n    private var displayedLandlineID: String {\n        landlineID.isEmpty ? "Starting Iroh…" : landlineID\n    }\n\n    var body: some View {\n        ZStack(alignment: .topLeading) {\n            RoundedRectangle(cornerRadius: 16, style: .continuous)\n                .fill(Color.white.opacity(0.95))\n\n            Button(action: onClose) {\n                ZStack {\n                    RoundedRectangle(cornerRadius: 10, style: .continuous)\n                        .fill(closeHovered ? Color.black.opacity(0.035) : .clear)\n\n                    Image(systemName: "xmark")\n                        .font(.system(size: 14, weight: .semibold))\n                        .foregroundStyle(Color(red: 23/255, green: 23/255, blue: 23/255))\n                }\n                .frame(width: 32, height: 32)\n                .contentShape(Rectangle())\n            }\n            .buttonStyle(.plain)\n            .scaleEffect(closeHovered ? 1.05 : 1.0)\n            .animation(.easeOut(duration: 0.10), value: closeHovered)\n            .offset(x: 280, y: 8)\n            .onHover { closeHovered = $0 }\n\n            RoundedRectangle(cornerRadius: 12, style: .continuous)\n                .fill(Color(red: 243/255, green: 243/255, blue: 243/255))\n                .frame(width: 272, height: 168)\n                .offset(x: 24, y: 40)\n\n            Text("Add someone")\n                .font(.custom("Inter Tight", size: 16).weight(.semibold))\n                .foregroundStyle(Color(red: 23/255, green: 23/255, blue: 23/255))\n                .frame(width: 240, height: 20, alignment: .leading)\n                .offset(x: 40, y: 56)\n\n            Text("Enter a Landline ID")\n                .font(.custom("Inter Tight", size: 14).weight(.medium))\n                .foregroundStyle(Color(red: 158/255, green: 163/255, blue: 158/255))\n                .frame(width: 240, height: 18, alignment: .leading)\n                .offset(x: 40, y: 122)\n\n            ZStack(alignment: .leading) {\n                RoundedRectangle(cornerRadius: 12, style: .continuous)\n                    .fill(Color(red: 235/255, green: 235/255, blue: 235/255))\n\n                TextField(\n                    "",\n                    text: $enteredID,\n                    prompt: Text("horse-window-apple-tv-consume-wall")\n                        .foregroundStyle(Color(red: 205/255, green: 209/255, blue: 205/255))\n                )\n                .textFieldStyle(.plain)\n                .font(.custom("Inter Tight", size: 12).weight(.medium))\n                .foregroundStyle(Color(red: 23/255, green: 23/255, blue: 23/255))\n                .padding(.horizontal, 8)\n                .focused($inputFocused)\n                .onSubmit(onSubmit)\n            }\n            .frame(width: 256, height: 48)\n            .offset(x: 32, y: 152)\n\n            RoundedRectangle(cornerRadius: 12, style: .continuous)\n                .fill(Color(red: 243/255, green: 243/255, blue: 243/255))\n                .frame(width: 272, height: 224)\n                .offset(x: 24, y: 232)\n\n            Text("Invite someone")\n                .font(.custom("Inter Tight", size: 16).weight(.semibold))\n                .foregroundStyle(Color(red: 23/255, green: 23/255, blue: 23/255))\n                .frame(width: 240, height: 20, alignment: .leading)\n                .offset(x: 40, y: 248)\n\n            Text("Your Landline ID")\n                .font(.custom("Inter Tight", size: 14).weight(.medium))\n                .foregroundStyle(Color(red: 158/255, green: 163/255, blue: 158/255))\n                .frame(width: 240, height: 18, alignment: .leading)\n                .offset(x: 40, y: 314)\n\n            Text(displayedLandlineID)\n                .font(.custom("Inter Tight", size: 12).weight(.medium))\n                .foregroundStyle(Color(red: 23/255, green: 23/255, blue: 23/255))\n                .lineLimit(1)\n                .truncationMode(.middle)\n                .padding(.horizontal, 16)\n                .frame(width: 256, height: 48, alignment: .leading)\n                .background(\n                    RoundedRectangle(cornerRadius: 12, style: .continuous)\n                        .fill(Color(red: 235/255, green: 235/255, blue: 235/255))\n                )\n                .offset(x: 32, y: 344)\n\n            Button(action: onCopy) {\n                Text(copied ? "Copied" : "Copy Landline ID")\n                    .font(.custom("Inter Tight", size: 14).weight(.semibold))\n                    .foregroundStyle(Color(red: 235/255, green: 235/255, blue: 235/255))\n                    .frame(width: 256, height: 48)\n                    .background(\n                        RoundedRectangle(cornerRadius: 16, style: .continuous)\n                            .fill(Color(red: 23/255, green: 23/255, blue: 23/255))\n                    )\n            }\n            .buttonStyle(.plain)\n            .offset(x: 32, y: 400)\n        }\n        .frame(width: 320, height: 472)\n        .onChange(of: isPresented) { _, presented in\n            if presented {\n                Task { @MainActor in\n                    try? await Task.sleep(for: .milliseconds(110))\n                    guard isPresented else { return }\n                    inputFocused = true\n                }\n            } else {\n                inputFocused = false\n            }\n        }\n        .onExitCommand(perform: onClose)\n    }\n}\n'''
content = replace_once(content, insert_marker, add_user_views + insert_marker, "ContentView AddUser views")

content_path.write_text(content)

iroh = iroh_path.read_text()

iroh = replace_once(
    iroh,
    '''    private var avatarDataBase64: String?\n    private var connectedPeerID: String?\n    private let playback = RemoteAudioPlayback()\n''',
    '''    private var avatarDataBase64: String?\n    private var connectedPeerID: String?\n    private var preferredRemoteSlotIndex: Int?\n    private let playback = RemoteAudioPlayback()\n''',
    "Iroh preferred slot state",
)

iroh = replace_once(
    iroh,
    '''    func connect(to rawEndpointId: String) {\n        guard let endpoint else {\n''',
    '''    func connect(to rawEndpointId: String, preferredSlotIndex: Int? = nil) {\n        guard let endpoint else {\n''',
    "Iroh connect signature",
)

iroh = replace_once(
    iroh,
    '''        guard !trimmed.isEmpty else { return }\n\n        disconnect(clearError: false)\n        connectionState = .connecting\n''',
    '''        guard !trimmed.isEmpty else { return }\n\n        let preferredSlot = preferredSlotIndex.flatMap { index in\n            remoteSlots.indices.contains(index) ? index : nil\n        }\n\n        disconnect(clearError: false)\n        preferredRemoteSlotIndex = preferredSlot\n        connectionState = .connecting\n''',
    "Iroh connect preferred slot",
)

iroh = replace_once(
    iroh,
    '''        connectedPeerID = nil\n        localTransmitGranted = false\n        remoteSpeakerID = nil\n''',
    '''        connectedPeerID = nil\n        preferredRemoteSlotIndex = nil\n        localTransmitGranted = false\n        remoteSpeakerID = nil\n''',
    "Iroh disconnect preferred slot",
)

iroh = replace_once(
    iroh,
    '''    private func insertOrUpdateRemote(_ participant: RemoteParticipant) {\n        if let index = remoteSlots.firstIndex(where: { $0?.id == participant.id }) {\n            remoteSlots[index] = participant\n            return\n        }\n        if let emptyIndex = remoteSlots.firstIndex(where: { $0 == nil }) {\n            remoteSlots[emptyIndex] = participant\n        }\n    }\n''',
    '''    private func insertOrUpdateRemote(_ participant: RemoteParticipant) {\n        if let index = remoteSlots.firstIndex(where: { $0?.id == participant.id }) {\n            remoteSlots[index] = participant\n            preferredRemoteSlotIndex = nil\n            return\n        }\n\n        if let preferredRemoteSlotIndex,\n           remoteSlots.indices.contains(preferredRemoteSlotIndex),\n           remoteSlots[preferredRemoteSlotIndex] == nil {\n            remoteSlots[preferredRemoteSlotIndex] = participant\n            self.preferredRemoteSlotIndex = nil\n            return\n        }\n\n        if let emptyIndex = remoteSlots.firstIndex(where: { $0 == nil }) {\n            remoteSlots[emptyIndex] = participant\n            preferredRemoteSlotIndex = nil\n        }\n    }\n''',
    "Iroh preferred slot insertion",
)

iroh_path.write_text(iroh)

print("Applied macOS Add User patch successfully")
