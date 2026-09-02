import AppKit
import Combine
import Foundation
import IrohLib

/// First integration of the proven Iroh spike into the real Landline UI.
///
/// This build is intentionally one-to-one and keeps peer discovery manual.
/// The existing RelayClient remains in the project as a known-good fallback,
/// but ContentView now sends/receives audio through this Iroh transport.
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

    /// The current integration is one-to-one, but it publishes the same seven
    /// fixed slots used by the established Landline dial so the UI does not
    /// need a transport-specific participant model.
    @Published private(set) var remoteSlots: [RemoteParticipant?] = Array(repeating: nil, count: 7)

    // Build-13 diagnostics retained in a temporary Settings panel.
    @Published private(set) var pathConnection = "—"
    @Published private(set) var pathRouteLabel = "Route"
    @Published private(set) var pathRoute = "—"
    @Published private(set) var pathLatency = "—"
    @Published private(set) var pathSelectionNote = ""
    @Published private(set) var landlineLatency = "—"
    @Published private(set) var pathCandidates: [PathDiagnostic] = []
    @Published private(set) var bytesSent: UInt64 = 0
    @Published private(set) var bytesReceived: UInt64 = 0

    private var endpoint: Endpoint?
    private var endpointBinding = false
    private var connection: Connection?
    private var sendStream: SendStream?
    private var recvStream: RecvStream?

    private var acceptTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var pathTask: Task<Void, Never>?
    private var lastPathLogSignature = ""
    private var nextPingNonce: UInt64 = 1
    private var outstandingPings: [UInt64: UInt64] = [:]

    private var displayName = "Caller"
    private var avatarKind = "default"
    private var avatarDataBase64: String?
    private var connectedPeerID: String?
    private let playback = RemoteAudioPlayback()

    var isConnected: Bool { connectionState == .connected }

    var stateLabel: String {
        if let lastError, !lastError.isEmpty {
            return "Error: \(lastError)"
        }
        if !endpointReady {
            return "Starting Iroh…"
        }
        switch connectionState {
        case .disconnected: return "Ready — waiting for a peer"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        }
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

    func connect(to rawEndpointId: String) {
        guard let endpoint else {
            lastError = "Iroh endpoint is not ready yet."
            return
        }

        let trimmed = rawEndpointId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        disconnect(clearError: false)
        connectionState = .connecting
        lastError = nil
        connectedPeerID = trimmed

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let peerId = try EndpointId.fromString(s: trimmed)
                let addr = EndpointAddr(id: peerId, relayUrl: nil, addresses: [])
                let conn = try await endpoint.connect(addr: addr, alpn: IrohWire.alpn)
                let bi = try await conn.openBi()

                // QUIC only exposes a newly opened stream to the accepting peer
                // after the initiator writes some data. The hello also carries
                // the profile needed to populate the real Landline dial.
                let hello = try self.currentHelloFrame()
                try await bi.send().writeAll(buf: hello)
                self.bytesSent += UInt64(hello.count)

                self.install(connection: conn, send: bi.send(), recv: bi.recv())
            } catch {
                self.connectionState = .disconnected
                self.lastError = error.localizedDescription
                self.connectedPeerID = nil
            }
        }
    }

    func disconnect() {
        disconnect(clearError: true)
    }

    /// Landline's PTT path retains the old RelayClient shape. Iroh has no
    /// central speaker arbiter, so this first one-to-one build grants local PTT
    /// immediately unless the connected peer is already talking.
    func beginTransmit() async -> Bool {
        guard isConnected, sendStream != nil else {
            localTransmitGranted = false
            return false
        }
        guard remoteSpeakerID == nil else {
            localTransmitGranted = false
            return false
        }

        do {
            try await sendFrame(.pttBegin)
            localTransmitGranted = true
            return true
        } catch {
            localTransmitGranted = false
            connectionFailed(error)
            return false
        }
    }

    func endTransmit() {
        let shouldSend = localTransmitGranted && isConnected
        localTransmitGranted = false
        guard shouldSend else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.sendFrame(.pttEnd)
            } catch {
                self.connectionFailed(error)
            }
        }
    }

    func sendAudioFrame(_ frame: CapturedAudioFrame) async {
        guard localTransmitGranted, isConnected else { return }
        do {
            try await sendFrame(.audio, payload: frame.networkPacket)
        } catch {
            connectionFailed(error)
        }
    }

    /// Application-level RTT over the exact framed stream carrying PTT/audio.
    func measureLandlineRTT() async {
        guard isConnected, sendStream != nil else { return }

        let nonce = nextPingNonce
        nextPingNonce &+= 1
        outstandingPings[nonce] = DispatchTime.now().uptimeNanoseconds
        landlineLatency = "Measuring…"

        do {
            try await sendFrame(.ping, payload: IrohWire.uint64Payload(nonce))
        } catch {
            outstandingPings.removeValue(forKey: nonce)
            landlineLatency = "Failed"
            connectionFailed(error)
        }
    }

    private func disconnect(clearError: Bool) {
        receiveTask?.cancel()
        pathTask?.cancel()
        receiveTask = nil
        pathTask = nil
        sendStream = nil
        recvStream = nil
        connection = nil
        connectionState = .disconnected
        connectedPeerID = nil
        localTransmitGranted = false
        remoteSpeakerID = nil
        remoteSpeakerName = nil
        remoteSlots = Array(repeating: nil, count: 7)
        outstandingPings.removeAll()
        playback.reset()
        resetPathDiagnostics()
        if clearError { lastError = nil }
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
                    self.install(connection: conn, send: bi.send(), recv: bi.recv())
                } catch {
                    if !Task.isCancelled {
                        self.lastError = error.localizedDescription
                        try? await Task.sleep(for: .milliseconds(350))
                    }
                }
            }
        }
    }

    private func install(connection: Connection, send: SendStream, recv: RecvStream) {
        receiveTask?.cancel()
        pathTask?.cancel()

        self.connection = connection
        self.sendStream = send
        self.recvStream = recv
        self.connectionState = .connected
        self.lastError = nil
        self.localTransmitGranted = false
        self.remoteSpeakerID = nil
        self.remoteSpeakerName = nil

        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.receiveLoop(recv)
        }

        pathTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.connection != nil {
                let paths = connection.paths()
                self.updatePathDiagnostics(paths)
                try? await Task.sleep(for: .milliseconds(750))
            }
        }

        // The accepting side has not written anything yet, and the initiating
        // side may have changed profile since its stream-opening hello. Sending
        // the current profile here is harmlessly idempotent and ensures both
        // Landline dials populate immediately.
        Task { @MainActor [weak self] in
            await self?.sendCurrentHello()
        }
    }

    private func receiveLoop(_ recv: RecvStream) async {
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
                    handleHello(payload)

                case .pttBegin:
                    let speakerID = connectedPeerID ?? remoteSlots.compactMap { $0 }.first?.id ?? "peer"
                    remoteSpeakerID = speakerID
                    remoteSpeakerName = remoteSlots.compactMap { $0 }.first(where: { $0.id == speakerID })?.name
                        ?? remoteSlots.compactMap { $0 }.first?.name
                        ?? "Caller"

                case .audio:
                    playback.enqueueNetworkPacket(payload)

                case .pttEnd:
                    remoteSpeakerID = nil
                    remoteSpeakerName = nil

                case .ping:
                    try await sendFrame(.pong, payload: payload)

                case .pong:
                    if let nonce = IrohWire.decodeUInt64Payload(payload),
                       let sentAt = outstandingPings.removeValue(forKey: nonce) {
                        let now = DispatchTime.now().uptimeNanoseconds
                        let elapsed = now >= sentAt ? now - sentAt : 0
                        landlineLatency = String(format: "%.1f ms", Double(elapsed) / 1_000_000)
                    }
                }
            }
        } catch {
            if !Task.isCancelled {
                connectionFailed(error)
            }
        }
    }

    private func sendCurrentHello() async {
        guard isConnected else { return }
        do {
            try await sendFrame(.hello, payload: try currentHelloPayload())
        } catch {
            connectionFailed(error)
        }
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

    private func handleHello(_ payload: Data) {
        guard !payload.isEmpty,
              let hello = try? JSONDecoder().decode(HelloMessage.self, from: payload)
        else { return }

        let remoteID = String(hello.endpointId.prefix(80))
        guard !remoteID.isEmpty, remoteID != endpointId else { return }
        connectedPeerID = remoteID

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
    }

    private func sendFrame(_ kind: IrohWire.Kind, payload: Data = Data()) async throws {
        guard let sendStream else { throw IrohClientError.notConnected }
        let data = IrohWire.frame(kind, payload: payload)
        try await sendStream.writeAll(buf: data)
        bytesSent += UInt64(data.count)
    }

    private func connectionFailed(_ error: Error) {
        lastError = error.localizedDescription
        disconnect(clearError: false)
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
            return
        }
        if let emptyIndex = remoteSlots.firstIndex(where: { $0 == nil }) {
            remoteSlots[emptyIndex] = participant
        }
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
            pathSelectionNote = ""
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
            pathRouteLabel = candidate.isRelay ? "Relay candidate" : (candidate.isIp ? "Direct candidate" : "Candidate")
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
