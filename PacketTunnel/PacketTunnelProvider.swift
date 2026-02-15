import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.netwraith.tunnel", category: "PacketTunnel")
    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)

    private var proxyLock = os_unfair_lock_s()
    private var _proxyHost: String = ""
    private var _proxyPort: Int = AppConstants.defaultProxyPort

    private var proxyHost: String {
        get { os_unfair_lock_lock(&proxyLock); defer { os_unfair_lock_unlock(&proxyLock) }; return _proxyHost }
        set { os_unfair_lock_lock(&proxyLock); defer { os_unfair_lock_unlock(&proxyLock) }; _proxyHost = newValue }
    }
    private var proxyPort: Int {
        get { os_unfair_lock_lock(&proxyLock); defer { os_unfair_lock_unlock(&proxyLock) }; return _proxyPort }
        set { os_unfair_lock_lock(&proxyLock); defer { os_unfair_lock_unlock(&proxyLock) }; _proxyPort = newValue }
    }

    private var bytesLock = os_unfair_lock_s()
    private var _totalBytesIn: Int = 0
    private var _totalBytesOut: Int = 0

    private func addBytes(inBytes: Int, outBytes: Int) {
        os_unfair_lock_lock(&bytesLock)
        _totalBytesIn += inBytes
        _totalBytesOut += outBytes
        os_unfair_lock_unlock(&bytesLock)
    }

    private var totalBytesIn: Int {
        os_unfair_lock_lock(&bytesLock); defer { os_unfair_lock_unlock(&bytesLock) }; return _totalBytesIn
    }
    private var totalBytesOut: Int {
        os_unfair_lock_lock(&bytesLock); defer { os_unfair_lock_unlock(&bytesLock) }; return _totalBytesOut
    }

    private var tunnelStartTime: TimeInterval = 0

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        os_log("Starting tunnel", log: log, type: .info)

        if let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration {
            _proxyHost = config["proxyHost"] as? String ?? ""
            _proxyPort = config["proxyPort"] as? Int ?? AppConstants.defaultProxyPort
        }

        if _proxyHost.isEmpty {
            _proxyHost = sharedDefaults?.string(forKey: SharedKeys.proxyHost) ?? ""
            let savedPort = sharedDefaults?.integer(forKey: SharedKeys.proxyPort) ?? 0
            if savedPort > 0 { _proxyPort = savedPort }
        }

        guard !_proxyHost.isEmpty, AppConstants.isValidHost(_proxyHost) else {
            os_log("No valid proxy host configured", log: log, type: .error)
            completionHandler(NSError(domain: "com.netwraith.tunnel", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "No valid proxy host configured"]))
            return
        }

        guard _proxyPort > 0, _proxyPort <= 65535 else {
            completionHandler(NSError(domain: "com.netwraith.tunnel", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "Invalid proxy port"]))
            return
        }

        tunnelStartTime = Date().timeIntervalSince1970

        let settings = createTunnelSettings()

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                os_log("Failed to set tunnel settings: %{public}@",
                       log: self?.log ?? .default, type: .error, error.localizedDescription)
                completionHandler(error)
                return
            }

            os_log("Tunnel active — all traffic routed to proxy", log: self?.log ?? .default, type: .info)

            self?.startPacketForwarding()

            self?.sharedDefaults?.set(true, forKey: SharedKeys.tunnelActive)
            self?.sharedDefaults?.set(Date().timeIntervalSince1970, forKey: SharedKeys.tunnelStartTime)

            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log("Stopping tunnel", log: log, type: .info)

        sharedDefaults?.set(false, forKey: SharedKeys.tunnelActive)
        sharedDefaults?.removeObject(forKey: SharedKeys.tunnelStartTime)

        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let message = try? JSONDecoder().decode(TunnelMessage.self, from: messageData) else {
            completionHandler?(nil)
            return
        }

        switch message.command {
        case .getStats:
            let startTime = sharedDefaults?.double(forKey: SharedKeys.tunnelStartTime) ?? tunnelStartTime
            let uptime = max(0, Date().timeIntervalSince1970 - startTime)
            let stats = TunnelStats(
                bytesIn: totalBytesIn,
                bytesOut: totalBytesOut,
                uptime: uptime
            )
            completionHandler?(try? JSONEncoder().encode(stats))

        case .updateProxy:
            if let data = message.payload,
               let config = try? JSONDecoder().decode(ProxyUpdate.self, from: data),
               AppConstants.isValidHost(config.host),
               config.port > 0, config.port <= 65535 {
                proxyHost = config.host
                proxyPort = config.port
                os_log("Proxy configuration updated", log: log, type: .info)
            } else {
                os_log("Invalid proxy update rejected", log: log, type: .error)
            }
            completionHandler?(nil)
        }
    }

    private func createTunnelSettings() -> NEPacketTunnelNetworkSettings {
        let host = proxyHost
        let port = proxyPort

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: AppConstants.tunnelRemoteAddress)

        let ipv4 = NEIPv4Settings(
            addresses: [AppConstants.tunnelLocalAddress],
            subnetMasks: [AppConstants.tunnelSubnetMask]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        // Exclude proxy server to avoid routing loops
        ipv4.excludedRoutes = [NEIPv4Route(destinationAddress: host, subnetMask: "255.255.255.255")]
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: AppConstants.dnsServers)
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        settings.mtu = NSNumber(value: AppConstants.tunnelMTU)

        let proxySettings = NEProxySettings()
        proxySettings.httpEnabled = true
        proxySettings.httpServer = NEProxyServer(address: host, port: port)
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = NEProxyServer(address: host, port: port)
        proxySettings.matchDomains = [""]
        proxySettings.excludeSimpleHostnames = false
        settings.proxySettings = proxySettings

        return settings
    }

    private func startPacketForwarding() {
        readPackets()
    }

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }

            var batchBytes = 0
            for packet in packets {
                batchBytes += packet.count
            }

            self.addBytes(inBytes: batchBytes, outBytes: 0)

            self.readPackets()
        }
    }
}

private struct ProxyUpdate: Codable {
    let host: String
    let port: Int
}
