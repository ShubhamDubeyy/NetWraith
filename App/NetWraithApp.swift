import SwiftUI

@main
struct NetWraithApp: App {
    @StateObject private var vpnManager = VPNManager()
    @StateObject private var networkMonitor = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vpnManager)
                .environmentObject(networkMonitor)
                .preferredColorScheme(.dark)
        }
    }
}
