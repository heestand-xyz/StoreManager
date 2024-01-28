import Foundation
import Combine
import StoreKit
import KeychainSwift

public final class StoreManager<SI: StoreItem>: ObservableObject {
    
    public enum PurchaseCompletion {
        case purchased
        case pending
        case userCancelled
    }
    
    public enum RestoreCompletion {
        case restored
        case alreadyAvailable
        case none
    }
    
    public enum StoreError: LocalizedError {
        case alreadyPrepared
        case productNotFound(id: String)
        case unknownError
        public var errorDescription: String? {
            switch self {
            case .alreadyPrepared:
                return "Already prepared"
            case .productNotFound(let id):
                return "Product not found: \(id)"
            case .unknownError:
                return "Unknown Error"
            }
        }
    }
    
    private let keychain: KeychainSwift = {
        let keychain = KeychainSwift()
        keychain.synchronizable = true
        return keychain
    }()
    
    private let connectivity = StoreConnectivity()
    
    @Published public private(set) var unlockedItems: Set<SI> = []
    
    @Published public private(set) var products: [SI: Product] = [:]
    
    private var cancelBag: Set<AnyCancellable> = []
    
    private var didPrepare: Bool = false
    
    public init() {

        unlockedItems = getUnlockedItems()

        print("Store Manager - Init with \(unlockedItems.count) unlocked items.")
        
        Task {
            await listen()
        }
#if !os(macOS)
        listenToApp()
#endif
        
        connectivity.$status
            .compactMap { [weak self] status in
                self?.connectivity.internetConnectionStatus(status: status)
            }
            .filter { status in
                print("Store Manager - Internet connectivity status:", status.name)
                return status == .connected
            }
            .sink { [weak self] status in
                guard let self else { return }
                Task {
                    do {
                        if !self.didPrepare {
                            try await self.prepare()
                        } else {
                            try await self.check()
                        }
                    } catch {
                        print("Store Manager - Connection check failed:", error)
                    }
                }
            }
            .store(in: &cancelBag)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
#if !os(macOS)

    func listenToApp() {
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    @objc func didBecomeActive() {
        Task {
            do {
                if !self.didPrepare {
                    try await self.prepare()
                } else {
                    try await self.check()
                }
            } catch {
                print("Store Manager - App active check failed:", error)
            }
        }
    }

#endif
    
    private func prepare() async throws {
        if didPrepare {
            throw StoreError.alreadyPrepared
        }
        try await setup()
        try await check()
        didPrepare = true
    }
    
    private func setup() async throws {
        let products = try await Product.products(for: SI.allCases.map(\.productID))
        for product in products {
            guard let item = SI(productID: product.id) else { continue }
            await MainActor.run {
                self.products[item] = product
            }
        }
        if SI.allCases.count != self.products.count {
            print("Store Manager - Warning:", 
                  "Not all products found.",
                  "Expected: \(SI.allCases.count).",
                  "Found: \(self.products.count).")
        }
    }
    
    /// Check for purchased items
    public func check() async throws {
        
        /// Purchases
        for (item, product) in self.products {
            
            switch item.type {
            case .oneTime:
                
                if isLocked(item) {
                    guard let result = await product.latestTransaction else { continue }
                    switch result {
                    case .verified(let transaction):
                        await MainActor.run {
                            unlock(item)
                        }
                        await transaction.finish()
                    case .unverified:
                        continue
                    }
                }
                
            case .subscription:
            
                guard let statuses: [Product.SubscriptionInfo.Status] = try await product.subscription?.status else { continue }
                let isActive: Bool = statuses.reduce(false) { isActive, status in
                    if isActive { return true }
                    switch status.state {
                    case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                        return true
                    case .expired, .revoked:
                        return false
                    default:
                        return false
                    }
                }
                if isActive && isLocked(item) {
                    await MainActor.run {
                        unlock(item)
                    }
                } else if !isActive && isUnlocked(item) {
                    await MainActor.run {
                        lock(item)
                    }
                }
            }
        }
    }
    
    private func listen() async {
        for await result in Transaction.updates {
            switch result {
            case .verified(let transaction):
                if let item: SI = .allCases.first(where: { $0.productID == transaction.productID }) {
                    await MainActor.run {
                        unlock(item)
                    }
                    await transaction.finish()
                } else if let subscriptionItem: SI = .allCases.first(where: { $0.productID == transaction.productID }) {
                    await MainActor.run {
                        unlock(subscriptionItem)
                    }
                    await transaction.finish()
                } else {
                    print("Store Manager - Warning:", "Transaction product not found.",
                          "Product ID:", transaction.productID)
                    continue
                }
            case .unverified:
                continue
            }
        }
    }
    
    func processPurchase(result: Product.PurchaseResult, for item: SI) async throws -> PurchaseCompletion {
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await MainActor.run {
                    unlock(item)
                }
                await transaction.finish()
                return .purchased
            case .unverified(_, let error):
                throw error
            }
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            throw StoreError.unknownError
        }
    }
    
    /// Syncs with App Store and checks for purchases
    public func restore() async throws {
        try await AppStore.sync()
        try await check()
    }
    
    private func isLocked(_ item: SI) -> Bool {
        !isUnlocked(item)
    }
    
    private func isUnlocked(_ item: SI) -> Bool {
        keychain.getBool(item.keychainKey) == true
    }
    
    private func getUnlockedItems() -> Set<SI> {
        Set(SI.allCases.filter({ item in
            isUnlocked(item)
        }))
    }
    
    private func unlock(_ item: SI) {
        print("Store Manager - Unlocked item:", item.productID)
        keychain.set(true, forKey: item.keychainKey)
        unlockedItems.insert(item)
    }
       
    private func lock(_ item: SI) {
        print("Store Manager - Locked item:", item.productID)
        keychain.set(false, forKey: item.keychainKey)
        unlockedItems.remove(item)
    }
    
#if DEBUG
    /// Debug only
    public func lockAllItems() {
        for item in SI.allCases {
            lock(item)
        }
    }
#endif
}
