import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vpnManager: VPNManager

    var body: some View {
        Form {
            Section("Connection") {
                InfoRow(label: "Tunnel IP", value: AppConstants.tunnelLocalAddress)
                InfoRow(label: "Remote", value: AppConstants.tunnelRemoteAddress)
                InfoRow(label: "MTU", value: "\(AppConstants.tunnelMTU)")
            }

            Section("Proxy") {
                InfoRow(label: "Target", value: vpnManager.proxyHost.isEmpty ? "Not set" : "\(vpnManager.proxyHost):\(vpnManager.proxyPort)")
                InfoRow(label: "Protocol", value: "HTTP/HTTPS CONNECT")
            }

            Section("About") {
                InfoRow(label: "Version", value: "2.0.0")
                InfoRow(label: "Min iOS", value: "15.0+")
            }

            Section {
                Button("Reset Proxy Settings", role: .destructive) {
                    vpnManager.proxyHost = ""
                    vpnManager.proxyPort = AppConstants.defaultProxyPort
                }
                .disabled(vpnManager.isConnected)
            }
        }
        .navigationTitle("Settings")
    }
}
