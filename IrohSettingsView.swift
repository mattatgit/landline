import AppKit
import SwiftUI

/// Temporary developer/test surface for manual Endpoint-ID pairing and the
/// Build-13 path diagnostics. It deliberately lives in macOS Settings so the
/// 320 × 672 product UI remains unchanged while transport work continues.
struct IrohSettingsView: View {
    @ObservedObject var iroh: IrohClient
    @AppStorage("LandlineIrohPeerEndpointID") private var peerEndpointID = ""
    @State private var showAllPaths = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Iroh test connection")
                        .font(.title2.weight(.semibold))
                    Text("Temporary manual pairing for the first integrated Landline + Iroh build.")
                        .foregroundStyle(.secondary)
                }

                GroupBox("This Mac") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(iroh.endpointId.isEmpty ? "Creating endpoint…" : iroh.endpointId)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Copy ID") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(iroh.endpointId, forType: .string)
                            }
                            .disabled(iroh.endpointId.isEmpty)
                        }

                        HStack(spacing: 8) {
                            Circle()
                                .fill(iroh.isConnected ? Color.green : Color.secondary.opacity(0.35))
                                .frame(width: 9, height: 9)
                            Text(iroh.stateLabel)
                                .font(.callout.weight(.medium))
                        }
                    }
                    .padding(6)
                }

                GroupBox("Peer") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Paste the other Mac’s Endpoint ID", text: $peerEndpointID)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        HStack {
                            Button("Connect") {
                                iroh.connect(to: peerEndpointID)
                            }
                            .keyboardShortcut(.return, modifiers: [])
                            .disabled(
                                peerEndpointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || !iroh.endpointReady
                                    || iroh.connectionState == .connecting
                            )

                            Button("Disconnect") {
                                iroh.disconnect()
                            }
                            .disabled(!iroh.isConnected)

                            Spacer()

                            if let participant = iroh.remoteSlots.compactMap({ $0 }).first {
                                Text("\(participant.name) connected")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(6)
                }

                GroupBox("Path diagnostics") {
                    VStack(alignment: .leading, spacing: 12) {
                        SwiftUI.Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                            pathRow("Connection", iroh.pathConnection)
                            pathRow(iroh.pathRouteLabel, iroh.pathRoute)
                            pathRow("Iroh RTT", iroh.pathLatency)
                            pathRow("Landline RTT", iroh.landlineLatency)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)

                        if !iroh.pathSelectionNote.isEmpty {
                            Text(iroh.pathSelectionNote)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Button("Measure Landline RTT") {
                                Task { @MainActor in
                                    await iroh.measureLandlineRTT()
                                }
                            }
                            .disabled(!iroh.isConnected || iroh.localTransmitGranted || iroh.remoteSpeakerID != nil)

                            Text("Use while both sides are idle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if !iroh.pathCandidates.isEmpty {
                            DisclosureGroup(
                                "All Iroh paths (\(iroh.pathCandidates.count))",
                                isExpanded: $showAllPaths
                            ) {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(iroh.pathCandidates) { candidate in
                                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                                            Text(candidate.isSelected ? "✓" : "·")
                                                .frame(width: 10, alignment: .center)
                                            Text(candidate.kind)
                                                .frame(width: 48, alignment: .leading)
                                            Text(candidate.route)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(candidate.latency)
                                                .frame(width: 58, alignment: .trailing)
                                        }
                                        .font(.system(size: 10, design: .monospaced))
                                        .fontWeight(candidate.isSelected ? .semibold : .regular)
                                        .textSelection(.enabled)
                                    }
                                }
                                .padding(.top, 5)
                            }
                            .font(.caption)
                        }

                        HStack {
                            Text("Sent \(formatBytes(iroh.bytesSent))")
                            Text("Received \(formatBytes(iroh.bytesReceived))")
                            Spacer()
                            Text("PCM16 · Iroh")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(6)
                }

                Text("Only one Mac needs to initiate the connection. Once connected, close Settings and use the normal Landline push-to-talk interface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
        }
        .frame(width: 590, height: 610)
    }

    @ViewBuilder
    private func pathRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label + ":")
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
        }
    }

    private func formatBytes(_ value: UInt64) -> String {
        if value < 1_024 { return "\(value) B" }
        if value < 1_048_576 { return String(format: "%.1f KB", Double(value) / 1_024) }
        return String(format: "%.1f MB", Double(value) / 1_048_576)
    }
}
