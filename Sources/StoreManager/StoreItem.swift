import Foundation

public enum StoreItemType: Sendable {
    case oneTime
    case subscription
}

public protocol StoreItem: Hashable, CaseIterable, Sendable {
    /// App Store Connect - Product ID
    var productID: String { get }
    var type: StoreItemType { get }
    var demoTime: TimeInterval? { get }
}

extension StoreItem {
    
    init?(productID: String) {
        guard let item = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = item
    }
}

extension StoreItem {
    
    var keychainKey: String {
        "store-item-\(productID)"
    }
    
    var keychainDemoDateKey: String {
        "\(keychainKey)_demo-date"
    }
}
