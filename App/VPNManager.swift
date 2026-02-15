import Foundation
import NetworkExtension
import Combine
import os.log

final class VPNManager: ObservableObject {

    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var connectionStatus: NEVPNStatus = .disconnected
    @Published var connectedDate: Date?
    @Published var lastError: String?
    @Published var bytesIn: Int = 0
    @Published var bytesOut: Int = 0

    @Published var proxyHost: String {
        didSet { sharedDefaults?.set(proxyHost, forKey: SharedKeys.proxyHost) }
    }
    @Published var proxyPort: Int {
        didSet { sharedDefaults?.set(proxyPort, forKey: SharedKeys.proxyPort) }
    }

    private let log = OSLog(subsystem: "com.netwraith.app", category: "VPNManager")
    private var manager: NETunnelProviderManager?
    private var statusObserver: Any?
    private var statsTimer: Timer?
    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)

    init() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        let savedHost = defaults?.string(forKey: SharedKeys.proxyHost) ?? ""
        let savedPort = defaults?.integer(forKey: SharedKeys.proxyPort).nonZero ?? AppConstants.defaultProxyPort
        _proxyHost = Published(initialValue: savedHost)
        _proxyPort = Published(initialValue: savedPort)

        DispatchQueue.main.async { [weak self] in
            self?.loadManagerAsync()
        }
    }

    // MARK: - Manager Setup

    private func loadManagerAsync() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error as NSError? {
                    os_log("Failed to load VPN manager: %{public}@", log: self.log, type: .error, error.localizedDescription)
                    if error.domain == "NEVPNErrorDomain" || error.domain == "NEConfigurationErrorDomain" {
                        self.lastError = "Network Extension entitlement missing. Install via TrollStore or use a signed build."
                    } else {
                        self.lastError = error.localizedDescription
                    }
                    self.manager = NETunnelProviderManager()
                    return
                }

                self.manager = managers?.first ?? NETunnelProviderManager()
                self.setupStatusObserver()
                self.updateStatus()
            }
        }
    }

    // MARK: - Connect / Disconnect

    func connect() {
        guard AppConstants.isValidHost(proxyHost) else {
            lastError = "Enter a valid IP address or hostname"
            return
        }
        guard proxyPort > 0 && proxyPort <= 65535 else {
            lastError = "Enter a valid port (1-65535)"
            return
        }
        guard let manager = manager else {
            lastError = "VPN manager not initialized"
            return
        }

        isConnecting = true
        lastError = nil

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppConstants.tunnelBundleIdentifier
        proto.serverAddress = "\(proxyHost):\(proxyPort)"
        proto.providerConfiguration = [
            "proxyHost": proxyHost,
            "proxyPort": proxyPort
        ] as [String: Any]
        proto.disconnectOnSleep = false

        manager.protocolConfiguration = proto
        manager.localizedDescription = "NetWraith Proxy"
        manager.isEnabled = true

        manager.saveToPreferences { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    os_log("Failed to save VPN: %{public}@", log: self?.log ?? .default, type: .error, error.localizedDescription)
                    self?.lastError = error.localizedDescription
                    self?.isConnecting = false
                }
                return
            }

            manager.loadFromPreferences { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.lastError = error.localizedDescription
                        self?.isConnecting = false
                    }
                    return
                }

                DispatchQueue.main.async {
                    do {
                        let session = manager.connection as? NETunnelProviderSession
                        try session?.startTunnel(options: nil)
                        os_log("VPN tunnel start requested", log: self?.log ?? .default, type: .info)
                        self?.startStatsPolling()
                    } catch {
                        os_log("Failed to start VPN: %{public}@", log: self?.log ?? .default, type: .error, error.localizedDescription)
                        self?.lastError = error.localizedDescription
                        self?.isConnecting = false
                    }
                }
            }
        }
    }

    func disconnect() {
        guard let manager = manager else { return }

        let session = manager.connection as? NETunnelProviderSession
        session?.stopTunnel()

        stopStatsPolling()
        os_log("VPN tunnel stop requested", log: log, type: .info)
    }

    func toggle() {
        if isConnected {
            disconnect()
        } else {
            connect()
        }
    }

    private func sendMessage(_ message: TunnelMessage, completion: ((Data?) -> Void)? = nil) {
        guard let session = manager?.connection as? NETunnelProviderSession,
              let data = try? JSONEncoder().encode(message) else {
            completion?(nil)
            return
        }

        do {
            try session.sendProviderMessage(data) { response in
                completion?(response)
            }
        } catch {
            os_log("IPC send failed", log: log, type: .error)
            completion?(nil)
        }
    }

    func refreshStats() {
        let message = TunnelMessage(command: .getStats, payload: nil)
        sendMessage(message) { [weak self] data in
            guard let data = data,
                  let stats = try? JSONDecoder().decode(TunnelStats.self, from: data) else { return }

            DispatchQueue.main.async {
                self?.bytesIn = stats.bytesIn
                self?.bytesOut = stats.bytesOut
            }
        }
    }

    private func startStatsPolling() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStats()
        }
    }

    private func stopStatsPolling() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    private func setupStatusObserver() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager?.connection,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatus()
        }
    }

    private func updateStatus() {
        guard let connection = manager?.connection else { return }

        connectionStatus = connection.status

        switch connection.status {
        case .connected:
            isConnected = true
            isConnecting = false
            connectedDate = connection.connectedDate
            lastError = nil

        case .connecting, .reasserting:
            isConnected = false
            isConnecting = true

        case .disconnected, .invalid:
            isConnected = false
            isConnecting = false
            connectedDate = nil
            stopStatsPolling()

        case .disconnecting:
            isConnecting = false

        @unknown default:
            break
        }
    }
}

private extension Int {
    var nonZero: Int? {
        self != 0 ? self : nil
    }
}
