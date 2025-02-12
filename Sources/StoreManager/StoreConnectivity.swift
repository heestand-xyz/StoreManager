//
//  Created by Nayem Mufakkharul on 2023/09/06.
//

import Foundation
import Connectivity

@MainActor
@Observable
public final class StoreConnectivity {
    
    public enum InternetConnectionStatus: Sendable {
        case connected
        case disconnected
        case notDetermined
        var name: String {
            switch self {
            case .connected:
                "Connected"
            case .disconnected:
                "Disconnected"
            case .notDetermined:
                "Not determined"
            }
        }
    }
    
    var status: ConnectivityStatus = .determining {
        didSet {
            internetConnectionStatusContinuation.yield(internetConnectionStatus)
        }
    }
    
    /// Used by ``StoreManager``
    let (internetConnectionStatusStream, internetConnectionStatusContinuation) = AsyncStream<InternetConnectionStatus>.makeStream()
    
    private let connectivity = Connectivity()
    
    init() {
        startConnectivityNotifier()
    }
    
    private func startConnectivityNotifier() {
        connectivity.startNotifier()
        connectivity.whenConnected = { [weak self] connectivity in
            Task { @MainActor in
                self?.status = connectivity.status
            }
        }
        connectivity.whenDisconnected = { [weak self] connectivity in
            Task { @MainActor in
                self?.status = connectivity.status
            }
        }
    }
    
    var internetConnectionStatus: InternetConnectionStatus {
        Self.internetConnectionStatus(status: status)
    }
    
    private static func internetConnectionStatus(status: ConnectivityStatus) -> InternetConnectionStatus {
        switch status {
        case .connected,
                .connectedViaCellular,
                .connectedViaEthernet,
                .connectedViaWiFi:
            return .connected
        case .connectedViaCellularWithoutInternet,
                .connectedViaEthernetWithoutInternet,
                .connectedViaWiFiWithoutInternet,
                .notConnected:
            return .disconnected
        case .determining:
            return .notDetermined
        }
    }
}
