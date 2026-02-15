import SwiftUI
import NetworkExtension

struct ContentView: View {
    @EnvironmentObject var vpnManager: VPNManager
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @State private var portText: String = ""
    @FocusState private var focusedField: Field?

    enum Field { case host, port }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    statusIndicator
                    proxyConfigCard
                    connectButton
                    if vpnManager.isConnected {
                        statsCard
                        connectionInfoCard
                    }
                    if let error = vpnManager.lastError {
                        errorBanner(error)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("NetWraith")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
            .onAppear {
                portText = "\(vpnManager.proxyPort)"
            }
        }
    }

    private var statusIndicator: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(statusColor.opacity(0.3))
                    .frame(width: 70, height: 70)

                Image(systemName: vpnManager.isConnected ? "shield.lefthalf.filled" : "shield.slash")
                    .font(.system(size: 32))
                    .foregroundColor(statusColor)
            }

            Text(statusText)
                .font(.title3.bold())
                .foregroundColor(statusColor)

            HStack(spacing: 6) {
                Image(systemName: networkMonitor.interfaceIcon)
                    .foregroundColor(.secondary)
                Text(networkMonitor.interfaceName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if vpnManager.isConnected {
                Text("Proxy: \(vpnManager.proxyHost):\(vpnManager.proxyPort)")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }

            if vpnManager.isConnected, let date = vpnManager.connectedDate {
                Text("Connected \(date, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var proxyConfigCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Proxy Configuration", systemImage: "server.rack")
                .font(.headline)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "network")
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    TextField("Burp Suite IP (e.g. 192.168.1.100)", text: $vpnManager.proxyHost)
                        .keyboardType(.decimalPad)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .host)
                }

                HStack(spacing: 12) {
                    Image(systemName: "number")
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    TextField("Port (default: 8080)", text: $portText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .port)
                        .onChange(of: portText) { newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue { portText = filtered }
                            if let port = Int(filtered), port > 0, port <= 65535, port != vpnManager.proxyPort {
                                vpnManager.proxyPort = port
                            }
                        }
                }
            }

            Text("Enter your Burp Suite listener address. The VPN will route all HTTP/HTTPS traffic through this proxy. Ensure Burp's CA certificate is installed on the device.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .disabled(vpnManager.isConnected || vpnManager.isConnecting)
        .opacity(vpnManager.isConnected ? 0.6 : 1.0)
    }

    private var connectButton: some View {
        Button {
            focusedField = nil
            vpnManager.toggle()
        } label: {
            HStack(spacing: 8) {
                if vpnManager.isConnecting {
                    ProgressView()
                        .tint(.white)
                }
                Text(vpnManager.isConnected ? "Disconnect" : "Start Interception")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(vpnManager.isConnected ? Color.red : Color.green)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .disabled(vpnManager.isConnecting)
    }

    private var statsCard: some View {
        HStack(spacing: 16) {
            StatBox(
                title: "Data In",
                value: formatBytes(vpnManager.bytesIn),
                icon: "arrow.down.circle.fill",
                color: .green
            )
            StatBox(
                title: "Data Out",
                value: formatBytes(vpnManager.bytesOut),
                icon: "arrow.up.circle.fill",
                color: .orange
            )
        }
    }

    private var connectionInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connection Details", systemImage: "info.circle")
                .font(.headline)

            InfoRow(label: "Tunnel IP", value: AppConstants.tunnelLocalAddress)
            InfoRow(label: "Proxy Target", value: "\(vpnManager.proxyHost):\(vpnManager.proxyPort)")
            InfoRow(label: "MTU", value: "\(AppConstants.tunnelMTU)")
            InfoRow(label: "Network", value: networkMonitor.interfaceName)
            InfoRow(label: "Status", value: vpnManager.connectionStatus.displayName)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }

    private var statusColor: Color {
        if vpnManager.isConnected { return .green }
        if vpnManager.isConnecting { return .yellow }
        return .gray
    }

    private var statusText: String {
        if vpnManager.isConnected { return "Intercepting Traffic" }
        if vpnManager.isConnecting { return "Connecting..." }
        return "Disconnected"
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospaced())
        }
    }
}

extension NEVPNStatus {
    var displayName: String {
        switch self {
        case .invalid:       return "Invalid"
        case .disconnected:  return "Disconnected"
        case .connecting:    return "Connecting"
        case .connected:     return "Connected"
        case .reasserting:   return "Reconnecting"
        case .disconnecting: return "Disconnecting"
        @unknown default:    return "Unknown"
        }
    }
}
