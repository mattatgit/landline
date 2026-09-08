import Foundation

/// Framing layer for Landline's Swift/Iroh transport.
///
/// Protocol v2 keeps the proven v1 hello/PTT/audio/ping frame layout and adds
/// one membership frame used to form a direct peer mesh for group calls.
enum IrohWire {
    static let alpn = Data("landline-iroh-audio/2".utf8)

    enum Kind: UInt8 {
        case hello = 1
        case pttBegin = 2
        case audio = 3
        case pttEnd = 4
        case ping = 5
        case pong = 6
        case membership = 7
    }

    static let headerSize = 5
    static let maximumPayloadSize = 256 * 1024

    static func frame(_ kind: Kind, payload: Data = Data()) -> Data {
        var result = Data(capacity: headerSize + payload.count)
        result.append(kind.rawValue)
        var length = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(payload)
        return result
    }

    static func uint64Payload(_ value: UInt64) -> Data {
        var littleEndian = value.littleEndian
        return withUnsafeBytes(of: &littleEndian) { Data($0) }
    }

    static func decodeUInt64Payload(_ data: Data) -> UInt64? {
        guard data.count == MemoryLayout<UInt64>.size else { return nil }
        return data.enumerated().reduce(UInt64(0)) { partial, item in
            partial | (UInt64(item.element) << UInt64(item.offset * 8))
        }
    }

    static func decodeHeader(_ data: Data) -> (Kind, Int)? {
        guard data.count == headerSize,
              let kind = Kind(rawValue: data[0])
        else { return nil }

        let count = UInt32(data[1])
            | (UInt32(data[2]) << 8)
            | (UInt32(data[3]) << 16)
            | (UInt32(data[4]) << 24)
        guard count <= maximumPayloadSize else { return nil }
        return (kind, Int(count))
    }
}
