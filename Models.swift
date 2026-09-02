import Foundation
import SwiftUI

struct Contact: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var avatarAsset: String
    var isOnline: Bool
    var isTalking: Bool
}

/// A real participant learned from the active network transport. Remote users are assigned to one
/// of seven fixed dial slots by the transport and keep that slot until they leave.
struct RemoteParticipant: Identifiable, Equatable {
    let id: String
    var name: String
    var avatarData: Data?
    var usesDefaultAvatar: Bool
}

enum MicState {
    case muted
    case talking
}
