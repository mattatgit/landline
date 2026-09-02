import AppKit
import Combine
import Foundation

/// Development configuration for the first Landline network transport.
///
/// Xcode environment variables take priority. A compiled build can be pointed
/// at another relay using UserDefaults, for example:
///   defaults write com.landline.prototype.mac LandlineRelayURL "ws://192.168.1.20:8787"
enum RelayConfiguration {
    static var relayURL: URL? {
        let environment = ProcessInfo.processInfo.environment
        let configured = environment["LANDLINE_RELAY_URL"]
            ?? UserDefaults.standard.string(forKey: "LandlineRelayURL")
            ?? "ws://127.0.0.1:8787"
        return URL(string: configured)
    }

    static var room: String {
        let environment = ProcessInfo.processInfo.environment
        let value = environment["LANDLINE_ROOM"]
            ?? UserDefaults.standard.string(forKey: "LandlineRoom")
            ?? "main"
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "main" : trimmed
    }
}

@MainActor
final class RelayClient: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var remoteSpeakerName: String?
    @Published private(set) var remoteSpeakerID: String?
    @Published private(set) var localTransmitGranted = false

    /// Slots 0...6 correspond to dial positions 1...7 clockwise after the
    /// local user's fixed 12 o'clock position. A departing user clears only
    /// their slot; a newly joining user takes the next available empty slot.
    @Published private(set) var remoteSlots: [RemoteParticipant?] = Array(repeating: nil, count: 7)

    let clientID = UUID().uuidString

    private var desiredConnection = false
    private var displayName = "Caller"
    private var avatarKind = "default"
    private var avatarDataBase64: String?
    private var socket: URLSessionWebSocketTask?
    private var connectionLoopTask: Task<Void, Never>?
    private let playback = RemoteAudioPlayback()

    func start(displayName: String, avatarImage: NSImage? = nil, usesDefaultAvatar: Bool = true) {
        setLocalProfile(displayName: displayName, avatarImage: avatarImage, usesDefaultAvatar: usesDefaultAvatar)
        guard !desiredConnection else { return }
        desiredConnection = true

        connectionLoopTask?.cancel()
        connectionLoopTask = Task { @MainActor [weak self] in
            await self?.connectionLoop()
        }
    }

    func stop() {
        desiredConnection = false
        connectionLoopTask?.cancel()
        connectionLoopTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connectionState = .disconnected
        localTransmitGranted = false
        remoteSpeakerID = nil
        remoteSpeakerName = nil
        remoteSlots = Array(repeating: nil, count: 7)
        playback.reset()
    }

    func setOutputVolume(_ value: Double) {
        playback.setVolume(value)
    }

    func updateProfile(name: String, avatarImage: NSImage?, usesDefaultAvatar: Bool) {
        setLocalProfile(displayName: name, avatarImage: avatarImage, usesDefaultAvatar: usesDefaultAvatar)
        guard connectionState == .connected else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            var payload: [String: Any] = [
                "type": "profile",
                "name": self.displayName,
                "avatarKind": self.avatarKind
            ]
            if let avatarDataBase64 = self.avatarDataBase64 {
                payload["avatarData"] = avatarDataBase64
            }
            await self.sendJSON(payload)
        }
    }

    func beginTransmit() {
        localTransmitGranted = false
        guard connectionState == .connected else { return }
        Task { @MainActor [weak self] in
            await self?.sendJSON(["type": "ptt_start"])
        }
    }

    func endTransmit() {
        localTransmitGranted = false
        guard connectionState == .connected else { return }
        Task { @MainActor [weak self] in
            await self?.sendJSON(["type": "ptt_stop"])
        }
    }

    func sendAudioFrame(_ frame: CapturedAudioFrame) async {
        guard localTransmitGranted,
              connectionState == .connected,
              let socket
        else { return }

        do {
            try await socket.send(.data(frame.networkPacket))
        } catch {
            NSLog("Landline relay audio send failed: %@", error.localizedDescription)
        }
    }

    private func connectionLoop() async {
        while desiredConnection, !Task.isCancelled {
            guard let url = RelayConfiguration.relayURL else {
                NSLog("Landline relay URL is invalid")
                connectionState = .disconnected
                return
            }

            connectionState = .connecting
            let candidate = URLSession.shared.webSocketTask(with: url)
            socket = candidate
            candidate.resume()

            do {
                try await candidate.send(.string(try helloJSONString()))
                guard desiredConnection, !Task.isCancelled, socket === candidate else {
                    candidate.cancel(with: .goingAway, reason: nil)
                    return
                }

                connectionState = .connected
                NSLog("Landline relay connected: %@ (room %@)", url.absoluteString, RelayConfiguration.room)
                try await receiveLoop(candidate)
            } catch {
                if desiredConnection, !Task.isCancelled {
                    NSLog("Landline relay disconnected: %@", error.localizedDescription)
                }
            }

            if socket === candidate {
                socket = nil
            }
            connectionState = .disconnected
            localTransmitGranted = false
            remoteSpeakerID = nil
            remoteSpeakerName = nil
            remoteSlots = Array(repeating: nil, count: 7)
            playback.reset()

            guard desiredConnection, !Task.isCancelled else { break }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func receiveLoop(_ candidate: URLSessionWebSocketTask) async throws {
        while desiredConnection, !Task.isCancelled, socket === candidate {
            let message = try await candidate.receive()
            switch message {
            case .string(let string):
                handleTextMessage(string)
            case .data(let data):
                // The relay only sends binary frames from the active *remote*
                // speaker. URLSessionWebSocketTask preserves binary messages.
                playback.enqueueNetworkPacket(data)
            @unknown default:
                break
            }
        }
    }

    private func handleTextMessage(_ string: String) {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "welcome":
            remoteSlots = Array(repeating: nil, count: 7)
            if let peers = json["peers"] as? [[String: Any]] {
                for peerJSON in peers.prefix(7) {
                    if let participant = participant(from: peerJSON) {
                        insertOrUpdateRemote(participant)
                    }
                }
            }

        case "peer_joined":
            if let participant = participant(from: json) {
                insertOrUpdateRemote(participant)
            }

        case "peer_updated":
            if let participant = participant(from: json) {
                insertOrUpdateRemote(participant)
                if remoteSpeakerID == participant.id {
                    remoteSpeakerName = participant.name
                }
            }

        case "peer_left":
            guard let clientID = json["clientID"] as? String else { return }
            clearRemote(clientID: clientID)
            if remoteSpeakerID == clientID {
                remoteSpeakerID = nil
                remoteSpeakerName = nil
            }

        case "speaker_granted":
            if let speakerID = json["speakerID"] as? String, speakerID == clientID {
                localTransmitGranted = true
            }

        case "speaker_denied":
            localTransmitGranted = false
            if let name = json["speakerName"] as? String {
                NSLog("Landline PTT denied; %@ is already talking", name)
            }

        case "speaker_started":
            guard let speakerID = json["speakerID"] as? String else { return }
            if speakerID == clientID {
                localTransmitGranted = true
                remoteSpeakerID = nil
                remoteSpeakerName = nil
            } else {
                remoteSpeakerID = speakerID
                let rosterName = remoteSlots.compactMap { $0 }.first(where: { $0.id == speakerID })?.name
                remoteSpeakerName = normalizedName(json["name"] as? String ?? rosterName ?? "Caller")
            }

        case "speaker_stopped":
            guard let speakerID = json["speakerID"] as? String else { return }
            if speakerID == clientID {
                localTransmitGranted = false
            }
            if remoteSpeakerID == speakerID {
                remoteSpeakerID = nil
                remoteSpeakerName = nil
            }

        default:
            break
        }
    }

    private func sendJSON(_ dictionary: [String: Any]) async {
        guard connectionState == .connected, let socket else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: dictionary)
            guard let string = String(data: data, encoding: .utf8) else { return }
            try await socket.send(.string(string))
        } catch {
            NSLog("Landline relay message send failed: %@", error.localizedDescription)
        }
    }

    private func helloJSONString() throws -> String {
        var object: [String: Any] = [
            "type": "hello",
            "clientID": clientID,
            "name": displayName,
            "room": RelayConfiguration.room,
            "avatarKind": avatarKind
        ]
        if let avatarDataBase64 {
            object["avatarData"] = avatarDataBase64
        }

        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
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

    /// Compress custom avatars before sending them through presence messages.
    /// 128 × 128 is comfortably above the 48 pt dial rendering size while
    /// keeping JSON profile messages small enough for the development relay.
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

    private func participant(from json: [String: Any]) -> RemoteParticipant? {
        guard let rawID = json["clientID"] as? String else { return nil }
        let id = String(rawID.prefix(80))
        guard !id.isEmpty, id != clientID else { return nil }

        let name = normalizedName(json["name"] as? String ?? "Caller")
        let kind = json["avatarKind"] as? String ?? "default"

        if kind == "jpeg",
           let encoded = json["avatarData"] as? String,
           let avatarData = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) {
            return RemoteParticipant(id: id, name: name, avatarData: avatarData, usesDefaultAvatar: false)
        }

        return RemoteParticipant(id: id, name: name, avatarData: nil, usesDefaultAvatar: true)
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

    private func clearRemote(clientID: String) {
        guard let index = remoteSlots.firstIndex(where: { $0?.id == clientID }) else { return }
        remoteSlots[index] = nil
    }

    private func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Caller" : String(trimmed.prefix(48))
    }
}
