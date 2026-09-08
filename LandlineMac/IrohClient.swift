import AppKit
import Combine
import Foundation
import IrohLib

/// Landline's native Iroh transport.
///
/// Protocol v2 supports a direct full mesh of up to seven remote peers. Each
/// remote endpoint owns an independent QUIC connection/stream, so one peer
/// disconnecting does not disturb the rest of the group.
@MainActor
final class IrohClient: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
    }

    struct PathDiagnostic: Identifiable, Equatable {
        let id: String
        let isSelected: Bool
        let kind: String
        let route: String
        let latency: String
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var endpointReady = false
    @Published private(set) var endpointId = ""
    @Published private(set) var lastError: String?

    @Published private(set) var remoteSpeakerName: String?
    @Published private(set) var remoteSpeakerID: String?
    @Published private(set) var localTransmitGranted = false
    @Published private(set) var remoteSlots: [RemoteParticipant?] = Array(repeating: nil, count: 7)

    // Temporary Settings diagnostics. In a group these follow one selected peer
    // while global byte counters include traffic to/from all direct sessions.
    @Published private(set) var pathConnection = "—"
    @Published private(set) var pathRouteLabel = "Route"
    @Published private(set) var pathRoute = "—"
    @Published private(set) var pathLatency = "—"
    @Published private(set) var pathSelectionNote = ""
    @Published private(set) var landlineLatency = "—"
    @Published private(set) var pathCandidates: [PathDiagnostic] = []
    @Published private(set) var bytesSent: UInt64 = 0
    @Published private(set) var bytesReceived: UInt64 = 0

    private final class PeerSession {
        let id = UUID()
        let connection: Connection
        let send: SendStream
        let recv: RecvStream
        var peerID: String?
        let initiatedLocally: Bool
        var receiveTask: Task<Void, Never>?
        var pathTask: Task<Void, Never>?

        init(
            connection: Connection,
            send: SendStream,
            recv: RecvStream,
            peerID: String?,
            initiatedLocally: Bool
        ) {
            self.connection = connection
            self.send = send
            self.recv = recv
            self.peerID = peerID
            self.initiatedLocally = initiatedLocally
        }
    }

    private struct PingRecord {
        let sentAt: UInt64
        let sessionID: UUID
    }

    private var endpoint: Endpoint?
    private var endpointBinding = false
    private var acceptTask: Task<Void, Never>?

    private var sessions: [UUID: PeerSession] = [:]
    private var connectingPeerIDs: Set<String> = []
    private var preferredSlotByPeerID: [String: Int] = [:]
    private var diagnosticSessionID: UUID?

    private var lastPathLogSignature = ""
    private var nextPingNonce: UInt64 = 1
    private var outstandingPings: [UInt64: PingRecord] = [:]

    private var displayName = "Caller"
    private var avatarKind = "default"
    private var avatarDataBase64: String?
    private let playback = RemoteAudioPlayback()

    var connectedPeerCount: Int {
        sessions.values.reduce(into: 0) { count, session in
            if session.peerID != nil { count += 1 }
        }
    }

    var isConnected: Bool { connectedPeerCount > 0 }

    var stateLabel: String {
        if let lastError, !lastError.isEmpty {
            return "Error: \(lastError)"
        }
        if !endpointReady {
            return "Starting Iroh…"
        }
        if connectedPeerCount > 0 {
            return connectedPeerCount == 1
                ? "Connected to 1 peer"
                : "Connected to \(connectedPeerCount) peers"
        }
        if connectionState == .connecting {
            return "Connecting…"
        }
        return "Ready — waiting for peers"
    }

    func start(displayName: String, avatarImage: NSImage? = nil, usesDefaultAvatar: Bool = true) {
        setLocalProfile(displayName: displayName, avatarImage: avatarImage, usesDefaultAvatar: usesDefaultAvatar)
        guard endpoint == nil, !endpointBinding else { return }

        endpointBinding = true
        endpointReady = false
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let identity = PersistentIrohIdentity.loadOrCreate()
                let ep = try await Endpoint.bind(
                    options: EndpointOptions(
                        preset: presetN0(),
                        secretKey: identity.secretKey.toBytes()
                    )
                )
                try ep.setAlpns(alpns: [IrohWire.alpn])
                self.endpoint = ep
                self.endpointBinding = false
                self.endpointId = String(describing: try ep.id())
                self.endpointReady = true
                self.lastError = nil
                self.beginAcceptLoop(ep)
                self.updateConnectionState()
            } catch {
                self.endpointBinding = false
                self.endpointReady = false
                self.lastError = error.localizedDescription
            }
        }
    }

    func stop() {
        disconnect()
        acceptTask?.cancel()
        acceptTask = nil

        let ep = endpoint
        endpoint = nil
        endpointBinding = false
        endpointReady = false
        endpointId = ""

        Task {
            try? await ep?.close()
        }
    }

    func setOutputVolume(_ value: Double) {
        playback.setVolume(value)
    }

    func updateProfile(name: String, avatarImage: NSImage?, usesDefaultAvatar: Bool) {
        setLocalProfile(displayName: name, avatarImage: avatarImage, usesDefaultAvatar: usesDefaultAvatar)
        guard isConnected else { return }

        Task { @MainActor [weak self] in
            await self?.sendCurrentHello()
        }
    }

    /// Adds one peer without disconnecting any existing peers. The explicit
    /// connection becomes a seed for mesh membership discovery.
    func connect(to rawEndpointId: String, preferredSlotIndex: Int? = nil) {
        guard let endpoint else {
            lastError = "Iroh endpoint is not ready yet."
            return
        }

        let trimmed = normalizedEndpointID(rawEndpointId)
        guard !trimmed.isEmpty, trimmed != endpointId else { return }
        guard session(forPeerID: trimmed) == nil, !connectingPeerIDs.contains(trimmed) else { return }

        let existingParticipant = remoteSlots.contains(where: { $0?.id == trimmed })
        guard existingParticipant || remoteSlots.contains(where: { $0 == nil }) else {
            lastError = "Landline already has seven remote users."
            return
        }

        if let preferredSlotIndex,
           remoteSlots.indices.contains(preferredSlotIndex),
           remoteSlots[preferredSlotIndex] == nil {
            preferredSlotByPeerID[trimmed] = preferredSlotIndex
        }

        connectingPeerIDs.insert(trimmed)
        lastError = nil
        updateConnectionState()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let peerId = try EndpointId.fromString(s: trimmed)
                let addr = EndpointAddr(id: peerId, relayUrl: nil, addresses: [])
                let conn = try await endpoint.connect(addr: addr, alpn: IrohWire.alpn)
                let bi = try await conn.openBi()

                // A newly opened QUIC stream is not visible to the accepting
                // endpoint until the initiator writes. Hello performs that first
                // write and gives the peer enough identity to bind the session.
                let hello = try self.currentHelloFrame()
                try await bi.send().writeAll(buf: hello)
                self.bytesSent += UInt64(hello.count)

                self.connectingPeerIDs.remove(trimmed)
                self.install(
                    connection: conn,
                    send: bi.send(),
                    recv: bi.recv(),
                    expectedPeerID: trimmed,
                    initiatedLocally: true
                )
            } catch {
                self.connectingPeerIDs.remove(trimmed)
                self.preferredSlotByPeerID.removeValue(forKey: trimmed)
                self.lastError = error.localizedDescription
                self.updateConnectionState()
            }
        }
    }

    /// Disconnects the whole local group. Individual network failures use
    /// removeSession instead and therefore leave other peers untouched.
    func disconnect() {
        let currentSessions = Array(sessions.values)
        sessions.removeAll()
        connectingPeerIDs.removeAll()
        preferredSlotByPeerID.removeAll()

        for session in currentSessions {
            session.receiveTask?.cancel()
            session.pathTask?.cancel()
        }

        diagnosticSessionID = nil
        localTransmitGranted = false
        remoteSpeakerID = nil
        remoteSpeakerName = nil
        remoteSlots = Array(repeating: nil, count: 7)
        outstandingPings.removeAll()
        playback.reset()
        resetPathDiagnostics()
        lastError = nil
        updateConnectionState()
    }

    /// Local PTT remains available with zero peers. With peers online, pttBegin
    /// is broadcast to every direct session. A deterministic endpoint-ID tie
    /// break resolves near-simultaneous presses to one speaker on all clients.
    func beginTransmit() async -> Bool {
        guard endpointReady else {
            localTransmitGranted = false
            return false
        }
        guard remoteSpeakerID == nil else {
            localTransmitGranted = false
            return false
        }

        localTransmitGranted = true
        await broadcastFrame(.pttBegin)
        return true
    }

    func endTransmit() {
        let shouldSend = localTransmitGranted
        localTransmitGranted = false
        guard shouldSend else { return }

        Task { @MainActor [weak self] in
            await self?.broadcastFrame(.pttEnd)
        }
    }

    func sendAudioFrame(_ frame: CapturedAudioFrame) async {
        guard localTransmitGranted else { return }
        await broadcastFrame(.audio, payload: frame.networkPacket)
    }

    /// Application-level RTT is measured against the diagnostics peer rather
    /// than every member at once.
    func measureLandlineRTT() async {
        guard let session = diagnosticSession() else { return }

        let nonce = nextPingNonce
        nextPingNonce &+= 1
        outstandingPings[nonce] = PingRecord(
            sentAt: DispatchTime.now().uptimeNanoseconds,
            sessionID: session.id
        )
        landlineLatency = "Measuring…"

        do {
            try await sendFrame(.ping, payload: IrohWire.uint64Payload(nonce), to: session.id)
        } catch {
            outstandingPings.removeValue(forKey: nonce)
            landlineLatency = "Failed"
            failSession(session.id, error: error)
        }
    }

    private func beginAcceptLoop(_ endpoint: Endpoint) {
        acceptTask?.cancel()
        acceptTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    guard let incoming = try await endpoint.acceptNext() else { break }
                    let accepting = try await incoming.accept()
                    let conn = try await accepting.connect()
                    let bi = try await conn.acceptBi()
                    self.install(
                        connection: conn,
                        send: bi.send(),
                        recv: bi.recv(),
                        expectedPeerID: nil,
                        initiatedLocally: false
                    )
                } catch {
                    if !Task.isCancelled {
                        self.lastError = error.localizedDescription
                        try? await Task.sleep(for: .milliseconds(350))
                    }
                }
            }
        }
    }

    private func install(
        connection: Connection,
        send: SendStream,
        recv: RecvStream,
        expectedPeerID: String?,
        initiatedLocally: Bool
    ) {
        let session = PeerSession(
            connection: connection,
            send: send,
            recv: recv,
            peerID: expectedPeerID,
            initiatedLocally: initiatedLocally
        )
        sessions[session.id] = session

        if let expectedPeerID {
            connectingPeerIDs.remove(expectedPeerID)
        }

        if diagnosticSessionID == nil {
            diagnosticSessionID = session.id
        }

        lastError = nil
        updateConnectionState()

        session.receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.receiveLoop(sessionID: session.id, recv: recv)
        }

        session.pathTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.sessions[session.id] != nil {
                if self.diagnosticSessionID == session.id {
                    self.updatePathDiagnostics(connection.paths())
                }
                try? await Task.sleep(for: .milliseconds(750))
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.sendFrame(
                    .hello,
                    payload: try self.currentHelloPayload(),
                    to: session.id
                )
            } catch {
                self.failSession(session.id, error: error)
            }
        }
    }

    private func receiveLoop(sessionID: UUID, recv: RecvStream) async {
        do {
            while !Task.isCancelled {
                let header = try await recv.readExact(size: UInt32(IrohWire.headerSize))
                guard let (kind, payloadLength) = IrohWire.decodeHeader(header) else {
                    throw IrohClientError.badFrame
                }

                let payload: Data
                if payloadLength == 0 {
                    payload = Data()
                } else {
                    payload = try await recv.readExact(size: UInt32(payloadLength))
                }
                bytesReceived += UInt64(IrohWire.headerSize + payload.count)

                switch kind {
                case .hello:
                    handleHello(payload, sessionID: sessionID)

                case .pttBegin:
                    if let peerID = sessions[sessionID]?.peerID {
                        handleRemotePTTBegin(from: peerID)
                    }

                case .audio:
                    if let peerID = sessions[sessionID]?.peerID,
                       peerID == remoteSpeakerID,
                       !localTransmitGranted {
                        playback.enqueueNetworkPacket(payload)
                    }

                case .pttEnd:
                    if let peerID = sessions[sessionID]?.peerID,
                       remoteSpeakerID == peerID {
                        remoteSpeakerID = nil
                        remoteSpeakerName = nil
                        playback.reset()
                    }

                case .ping:
                    try await sendFrame(.pong, payload: payload, to: sessionID)

                case .pong:
                    handlePong(payload, sessionID: sessionID)

                case .membership:
                    handleMembership(payload)
                }
            }
        } catch {
            if !Task.isCancelled {
                failSession(sessionID, error: error)
            }
        }
    }

    private func handleHello(_ payload: Data, sessionID: UUID) {
        guard !payload.isEmpty,
              let hello = try? JSONDecoder().decode(HelloMessage.self, from: payload),
              let session = sessions[sessionID]
        else { return }

        let remoteID = normalizedEndpointID(hello.endpointId)
        guard !remoteID.isEmpty, remoteID != endpointId else { return }

        // If both clients manually initiate at the same time, both sides
        // keep the same physical QUIC connection: the lower endpoint ID's
        // outbound session. This avoids each Mac retaining opposite duplicates.
        let duplicates = sessions.values.filter { $0.id != sessionID && $0.peerID == remoteID }
        if !duplicates.isEmpty {
            let shouldKeepLocallyInitiated = endpointId < remoteID
            if session.initiatedLocally == shouldKeepLocallyInitiated {
                for duplicate in duplicates {
                    removeSession(duplicate.id, clearParticipant: false)
                }
            } else {
                removeSession(sessionID, clearParticipant: false)
                return
            }
        }

        session.peerID = remoteID
        connectingPeerIDs.remove(remoteID)

        let isExistingParticipant = remoteSlots.contains(where: { $0?.id == remoteID })
        if !isExistingParticipant && !remoteSlots.contains(where: { $0 == nil }) {
            removeSession(sessionID, clearParticipant: false)
            return
        }

        let participant: RemoteParticipant
        if hello.avatarKind == "jpeg",
           let encoded = hello.avatarData,
           let avatarData = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) {
            participant = RemoteParticipant(
                id: remoteID,
                name: normalizedName(hello.name),
                avatarData: avatarData,
                usesDefaultAvatar: false
            )
        } else {
            participant = RemoteParticipant(
                id: remoteID,
                name: normalizedName(hello.name),
                avatarData: nil,
                usesDefaultAvatar: true
            )
        }

        insertOrUpdateRemote(participant)

        if remoteSpeakerID == remoteID {
            remoteSpeakerName = participant.name
        }

        updateConnectionState()

        // A peer that joins while this Mac is already holding PTT needs the
        // current floor state before its first audio packet.
        if localTransmitGranted {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.sendFrame(.pttBegin, to: sessionID)
                } catch {
                    self.failSession(sessionID, error: error)
                }
            }
        }

        Task { @MainActor [weak self] in
            await self?.broadcastMembership()
        }
    }

    private func handleMembership(_ payload: Data) {
        guard let membership = try? JSONDecoder().decode(MembershipMessage.self, from: payload),
              endpointReady,
              !endpointId.isEmpty
        else { return }

        let candidates = Array(Set(membership.endpointIds.map { normalizedEndpointID($0) }))
            .filter { !$0.isEmpty && $0 != endpointId }
            .sorted()
            .prefix(7)

        for peerID in candidates {
            guard session(forPeerID: peerID) == nil,
                  !connectingPeerIDs.contains(peerID),
                  remoteSlots.contains(where: { $0 == nil })
            else { continue }

            // Exactly one side of a newly discovered pair initiates, avoiding a
            // connection storm as membership propagates through the mesh.
            if endpointId < peerID {
                connect(to: peerID)
            }
        }
    }

    private func broadcastMembership() async {
        let ids = Set(
            [endpointId]
                + remoteSlots.compactMap { $0?.id }
                + sessions.values.compactMap { $0.peerID }
        )
        let normalized = ids
            .map { normalizedEndpointID($0) }
            .filter { !$0.isEmpty }
            .sorted()
            .prefix(8)

        let message = MembershipMessage(endpointIds: Array(normalized))
        guard let payload = try? JSONEncoder().encode(message) else { return }
        await broadcastFrame(.membership, payload: payload)
    }

    private func handleRemotePTTBegin(from peerID: String) {
        // If local and remote begin nearly simultaneously, the lower endpoint
        // ID wins everywhere. The losing local sender broadcasts pttEnd so third
        // peers converge on the same floor owner.
        if localTransmitGranted {
            guard peerID < endpointId else { return }

            localTransmitGranted = false
            remoteSpeakerID = peerID
            remoteSpeakerName = participantName(for: peerID)
            playback.reset()

            Task { @MainActor [weak self] in
                await self?.broadcastFrame(.pttEnd)
            }
            return
        }

        if let currentSpeakerID = remoteSpeakerID {
            guard currentSpeakerID != peerID else { return }
            guard peerID < currentSpeakerID else { return }
            playback.reset()
        }

        remoteSpeakerID = peerID
        remoteSpeakerName = participantName(for: peerID)
    }

    private func handlePong(_ payload: Data, sessionID: UUID) {
        guard let nonce = IrohWire.decodeUInt64Payload(payload),
              let record = outstandingPings.removeValue(forKey: nonce),
              record.sessionID == sessionID
        else { return }

        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now >= record.sentAt ? now - record.sentAt : 0
        landlineLatency = String(format: "%.1f ms", Double(elapsed) / 1_000_000)
    }

    private func sendCurrentHello() async {
        guard isConnected else { return }
        guard let payload = try? currentHelloPayload() else { return }
        await broadcastFrame(.hello, payload: payload)
    }

    private func currentHelloFrame() throws -> Data {
        IrohWire.frame(.hello, payload: try currentHelloPayload())
    }

    private func currentHelloPayload() throws -> Data {
        let hello = HelloMessage(
            endpointId: endpointId,
            name: displayName,
            avatarKind: avatarKind,
            avatarData: avatarDataBase64
        )
        return try JSONEncoder().encode(hello)
    }

    private func broadcastFrame(_ kind: IrohWire.Kind, payload: Data = Data()) async {
        let sessionIDs = sessions.values
            .filter { $0.peerID != nil }
            .map(\.id)

        for sessionID in sessionIDs {
            do {
                try await sendFrame(kind, payload: payload, to: sessionID)
            } catch {
                failSession(sessionID, error: error)
            }
        }
    }

    private func sendFrame(
        _ kind: IrohWire.Kind,
        payload: Data = Data(),
        to sessionID: UUID
    ) async throws {
        guard let session = sessions[sessionID] else {
            throw IrohClientError.notConnected
        }
        let data = IrohWire.frame(kind, payload: payload)
        try await session.send.writeAll(buf: data)
        bytesSent += UInt64(data.count)
    }

    private func failSession(_ sessionID: UUID, error: Error) {
        lastError = error.localizedDescription
        removeSession(sessionID, clearParticipant: true)
    }

    private func removeSession(_ sessionID: UUID, clearParticipant: Bool) {
        guard let removed = sessions.removeValue(forKey: sessionID) else { return }

        removed.receiveTask?.cancel()
        removed.pathTask?.cancel()

        if let peerID = removed.peerID {
            connectingPeerIDs.remove(peerID)
            preferredSlotByPeerID.removeValue(forKey: peerID)

            if clearParticipant && self.session(forPeerID: peerID) == nil {
                removeRemoteParticipant(peerID)
            }

            if remoteSpeakerID == peerID {
                remoteSpeakerID = nil
                remoteSpeakerName = nil
                playback.reset()
            }
        }

        outstandingPings = outstandingPings.filter { $0.value.sessionID != sessionID }

        if diagnosticSessionID == sessionID {
            diagnosticSessionID = sessions.values.first(where: { $0.peerID != nil })?.id
            resetPathDiagnostics()
        }

        updateConnectionState()

        Task { @MainActor [weak self] in
            await self?.broadcastMembership()
        }
    }

    private func session(forPeerID peerID: String) -> PeerSession? {
        sessions.values.first(where: { $0.peerID == peerID })
    }

    private func diagnosticSession() -> PeerSession? {
        if let diagnosticSessionID,
           let current = sessions[diagnosticSessionID],
           current.peerID != nil {
            return current
        }
        if let current = sessions.values.first(where: { $0.peerID != nil }) {
            diagnosticSessionID = current.id
            return current
        }
        return nil
    }

    private func updateConnectionState() {
        if connectedPeerCount > 0 {
            connectionState = .connected
        } else if !connectingPeerIDs.isEmpty || !sessions.isEmpty {
            connectionState = .connecting
        } else {
            connectionState = .disconnected
        }
    }

    private func setLocalProfile(displayName: String, avatarImage: NSImage?, usesDefaultAvatar: Bool) {
        self.displayName = normalizedName(displayName)

        if !usesDefaultAvatar, let avatarImage, let encoded = encodeAvatarJPEG(avatarImage) {
            avatarKind = "jpeg"
            avatarDataBase64 = encoded
        } else {
            avatarKind = "default"
            avatarDataBase64 = nil
        }
    }

    private func encodeAvatarJPEG(_ image: NSImage) -> String? {
        let targetSize = NSSize(width: 128, height: 128)
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawOrigin = NSPoint(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2
        )

        let rendered = NSImage(size: targetSize)
        rendered.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: drawOrigin, size: drawSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1.0
        )
        rendered.unlockFocus()

        guard let tiff = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else { return nil }

        return jpeg.base64EncodedString()
    }

    private func insertOrUpdateRemote(_ participant: RemoteParticipant) {
        if let index = remoteSlots.firstIndex(where: { $0?.id == participant.id }) {
            remoteSlots[index] = participant
            preferredSlotByPeerID.removeValue(forKey: participant.id)
            return
        }

        if let preferredSlot = preferredSlotByPeerID[participant.id],
           remoteSlots.indices.contains(preferredSlot),
           remoteSlots[preferredSlot] == nil {
            remoteSlots[preferredSlot] = participant
            preferredSlotByPeerID.removeValue(forKey: participant.id)
            return
        }

        if let emptyIndex = remoteSlots.firstIndex(where: { $0 == nil }) {
            remoteSlots[emptyIndex] = participant
            preferredSlotByPeerID.removeValue(forKey: participant.id)
        }
    }

    private func removeRemoteParticipant(_ peerID: String) {
        guard let index = remoteSlots.firstIndex(where: { $0?.id == peerID }) else { return }
        remoteSlots[index] = nil
    }

    private func participantName(for peerID: String) -> String {
        remoteSlots.compactMap { $0 }.first(where: { $0.id == peerID })?.name ?? "Caller"
    }

    private func normalizedEndpointID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(80))
    }

    private func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Caller" : String(trimmed.prefix(48))
    }

    private func updatePathDiagnostics(_ paths: [PathSnapshot]) {
        pathCandidates = paths.enumerated().map { index, path in
            let kind = path.isRelay ? "Relay" : (path.isIp ? "Direct" : "Other")
            let route = Self.displayAddress(path.remoteAddr, relay: path.isRelay)
            return PathDiagnostic(
                id: "\(index)|\(kind)|\(path.remoteAddr)",
                isSelected: path.isSelected,
                kind: kind,
                route: route,
                latency: "\(path.rttMs) ms"
            )
        }

        let signature = paths.map { String(describing: $0) }.joined(separator: "\n")
        if signature != lastPathLogSignature {
            lastPathLogSignature = signature
            print("\n[Landline Iroh paths] \(paths.count) candidate(s)")
            for path in paths {
                let marker = path.isSelected ? "SELECTED" : "candidate"
                print("  [\(marker)] \(String(describing: path))")
            }
        }

        if let selected = paths.first(where: { $0.isSelected }) {
            pathSelectionNote = connectedPeerCount > 1
                ? "Showing one of \(connectedPeerCount) direct peer sessions"
                : ""
            if selected.isRelay {
                pathConnection = "Relay"
                pathRouteLabel = "Relay"
                pathRoute = Self.displayAddress(selected.remoteAddr, relay: true)
            } else if selected.isIp {
                pathConnection = "Direct"
                pathRouteLabel = "Peer address"
                pathRoute = Self.displayAddress(selected.remoteAddr, relay: false)
            } else {
                pathConnection = "Selected path"
                pathRouteLabel = "Route"
                pathRoute = selected.remoteAddr
            }
            pathLatency = "\(selected.rttMs) ms"
            return
        }

        if let candidate = paths.first {
            pathConnection = "Negotiating"
            pathRouteLabel = candidate.isRelay
                ? "Relay candidate"
                : (candidate.isIp ? "Direct candidate" : "Candidate")
            pathRoute = Self.displayAddress(candidate.remoteAddr, relay: candidate.isRelay)
            pathLatency = "\(candidate.rttMs) ms"
            pathSelectionNote = "No selected path reported yet"
        } else {
            pathConnection = "Waiting"
            pathRouteLabel = "Route"
            pathRoute = "—"
            pathLatency = "—"
            pathSelectionNote = "Waiting for Iroh path data"
        }
    }

    private func resetPathDiagnostics() {
        pathConnection = "—"
        pathRouteLabel = "Route"
        pathRoute = "—"
        pathLatency = "—"
        pathSelectionNote = ""
        landlineLatency = "—"
        pathCandidates = []
        lastPathLogSignature = ""
    }

    private static func displayAddress(_ raw: String, relay: Bool) -> String {
        guard relay, let url = URL(string: raw), let host = url.host else { return raw }
        return host
    }

    private struct HelloMessage: Codable {
        let endpointId: String
        let name: String
        let avatarKind: String
        let avatarData: String?
    }

    private struct MembershipMessage: Codable {
        let endpointIds: [String]
    }

    private enum IrohClientError: LocalizedError {
        case badFrame
        case notConnected

        var errorDescription: String? {
            switch self {
            case .badFrame: return "Received an invalid Landline Iroh frame."
            case .notConnected: return "The Iroh peer is not connected."
            }
        }
    }
}

private struct PersistentIrohIdentity {
    private static let defaultsKey = "landline.iroh.secretKey.v1"

    let secretKey: SecretKey

    static func loadOrCreate(defaults: UserDefaults = .standard) -> PersistentIrohIdentity {
        if let encoded = defaults.string(forKey: defaultsKey),
           let bytes = Data(base64Encoded: encoded),
           let parsed = try? SecretKey.fromBytes(bytes: bytes) {
            return PersistentIrohIdentity(secretKey: parsed)
        }

        let secret = SecretKey.generate()
        defaults.set(secret.toBytes().base64EncodedString(), forKey: defaultsKey)
        return PersistentIrohIdentity(secretKey: secret)
    }
}
