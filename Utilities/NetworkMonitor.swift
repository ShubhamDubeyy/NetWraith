import Foundation
import Network

final class NetworkMonitor: ObservableObject {

    @Published var isConnected: Bool = true
    @Published var connectionType: NWInterface.InterfaceType = .other

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.netwraith.networkmonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type ?? .other
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var interfaceName: String {
        switch connectionType {
        case .wifi:          return "Wi-Fi"
        case .cellular:      return "Cellular"
        case .wiredEthernet: return "Ethernet"
        default:             return "Unknown"
        }
    }

    var interfaceIcon: String {
        switch connectionType {
        case .wifi:          return "wifi"
        case .cellular:      return "antenna.radiowaves.left.and.right"
        case .wiredEthernet: return "cable.connector"
        default:             return "network"
        }
    }
}
