import Foundation

struct TunnelMessage: Codable {
    let command: Command
    let payload: Data?

    enum Command: String, Codable {
        case getStats
        case updateProxy
    }
}

struct TunnelStats: Codable {
    let bytesIn: Int
    let bytesOut: Int
    let uptime: TimeInterval
}
