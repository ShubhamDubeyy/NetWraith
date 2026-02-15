import Foundation

enum AppConstants {
    static let appGroupIdentifier = "group.com.netwraith.shared"
    static let mainBundleIdentifier = "com.netwraith.app"
    static let tunnelBundleIdentifier = "com.netwraith.app.packet-tunnel"

    static let tunnelLocalAddress = "10.8.0.2"
    static let tunnelRemoteAddress = "10.8.0.1"
    static let tunnelSubnetMask = "255.255.255.0"
    static let tunnelMTU = 1500

    static let defaultProxyPort = 8080
    static let dnsServers = ["8.8.8.8", "8.8.4.4"]

    static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }

        let octets = host.split(separator: ".")
        if octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) {
            return true
        }

        // RFC 1123 hostname
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        return host.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !host.hasPrefix("-") && !host.hasPrefix(".")
            && !host.hasSuffix("-") && !host.hasSuffix(".")
    }
}
