//
//  Created by Nayem Mufakkharul on 2023/09/06.
//

import Foundation
import Connectivity

final class StoreConnectivity: ObservableObject {
    
    enum InternetConnectionStatus {
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
    
    @Published var status: ConnectivityStatus = .determining
    
    private let connectivity = Connectivity()
    
    init() {
        startConnectivityNotifier()
    }
    
    private func startConnectivityNotifier() {
        connectivity.startNotifier()
        connectivity.whenConnected = { [weak self] connectivity in
            DispatchQueue.main.async {
                self?.status = connectivity.status
            }
        }
        connectivity.whenDisconnected = { [weak self] connectivity in
            DispatchQueue.main.async {
                self?.status = connectivity.status
            }
        }
    }
    
    var internetConnectionStatus: InternetConnectionStatus {
        internetConnectionStatus(status: status)
    }
    
    func internetConnectionStatus(status: ConnectivityStatus) -> InternetConnectionStatus {
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
