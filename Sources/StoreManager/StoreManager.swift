import Foundation
import Combine
import StoreKit
import KeychainSwift

@MainActor
@Observable
public final class StoreManager<SI: StoreItem> {
    
    public enum PurchaseCompletion {
        case purchased(Transaction)
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
    
    public private(set) var unlockedItems: Set<SI> = [] {
        didSet {
            unlockedItemsStreamContinuation.yield(unlockedItems)
        }
    }
    public let unlockedItemsStream: AsyncStream<Set<SI>>
    private let unlockedItemsStreamContinuation: AsyncStream<Set<SI>>.Continuation
    
    public private(set) var demoingItems: Set<SI> = [] {
        didSet {
            demoingStreamContinuation.yield(demoingItems)
        }
    }
    public let demoingStream: AsyncStream<Set<SI>>
    private let demoingStreamContinuation: AsyncStream<Set<SI>>.Continuation
    
    public private(set) var products: [SI: Product] = [:]
    
    public private(set) var internetConnectionStatus: StoreConnectivity.InternetConnectionStatus = .notDetermined
    
#if DEBUG
    public enum DebugAccess {
        case none
        case all
        case current
    }
    public var debugAccess: DebugAccess = .current {
        didSet {
            switch debugAccess {
            case .none:
                unlockedItems = []
            case .all:
                unlockedItems = Set(SI.allCases)
            case .current:
                unlockedItems = getUnlockedItems()
            }
        }
    }
#endif
    
    private let jsonDateDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    private let jsonDateEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    
    public init() {

        (unlockedItemsStream, unlockedItemsStreamContinuation) = AsyncStream.makeStream(
            of: Set<SI>.self,
            bufferingPolicy: .unbounded
        )
        
        (demoingStream, demoingStreamContinuation) = AsyncStream.makeStream(
            of: Set<SI>.self,
            bufferingPolicy: .unbounded
        )
        
        unlockedItems = getUnlockedItems()
        setupDemos()

        print("Store Manager - Init with \(unlockedItems.count) unlocked items.")
        
        Task {
            await listen()
        }
#if !os(macOS)
        listenToApp()
#endif
        
        Task {
            for await status in connectivity.internetConnectionStatusStream {
                await MainActor.run {
                    internetConnectionStatus = status
                }
                if status == .connected {
                    do {
                        try await check()
                    } catch {
                        print("Store Manager - Prepare or check failed:", error)
                    }
                }
            }
        }
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
                try await self.check()
            } catch {
                print("Store Manager - App active check failed:", error)
            }
        }
    }

#endif
    
    private func fetchProducts() async throws {
        let products = try await Product.products(for: SI.allCases.map(\.productID))
        for product in products {
            guard let item = SI(productID: product.id) else {
                print("Store Manager - Warning:",
                      "Product unknown.",
                      "ID: \(product.id)")
                continue
            }
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
        try await fetchProducts()
        
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
                let activeProductIDs: Set<String> = Set(statuses.compactMap { status in
                    switch status.state {
                    case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                        switch status.transaction {
                        case .verified(let transaction):
                            return transaction.productID
                        case .unverified:
                            return nil
                        }
                    case .expired, .revoked:
                        return nil
                    default:
                        return nil
                    }
                })
                let isItemActive: Bool = activeProductIDs.contains(item.productID)
                if isItemActive && isLocked(item) {
                    await MainActor.run {
                        unlock(item)
                    }
                } else if !isItemActive && isUnlocked(item) {
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
                await transaction.finish()
                do {
                    try await check()
                } catch {
                    print("Store Manager - Transaction update check failed:", error)
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
                return .purchased(transaction)
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
    
    @available(*, deprecated, renamed: "sync")
    public func restore() async throws {
        try await sync()
    }
    
    /// Syncs with App Store and checks for purchases.
    public func sync() async throws {
        try await AppStore.sync()
        try await check()
    }
    
    public func displayPrice(for item: SI) -> String? {
        products[item]?.displayPrice
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
    /// Debug mode only
    public func debugLockAllItems() {
        for item in SI.allCases {
            lock(item)
        }
    }
#endif
}

// MARK: - Demo

extension StoreManager {
    
    private func setupDemos() {
        for item in SI.allCases {
            demoIfNeeded(item)
        }
    }
    
    public func demoInfo(_ item: SI) -> DemoInfo {
        guard let time: TimeInterval = item.demoTime else {
            print("Store Manager - Demo Info - No valid demo time for item:", item.productID)
            return .notUsed
        }
        guard let data: Data = keychain.getData(item.keychainDemoDateKey) else {
            return .notUsed
        }
        do {
            let startDate: Date = try jsonDateDecoder.decode(Date.self, from: data)
            let isOngoing: Bool = startDate.distance(to: .now) < time
            return DemoInfo(state: isOngoing ? .ongoing : .used, startDate: startDate)
        } catch {
            print("Store Manager - Demo Info - Error decoding start date for item:", item.productID)
            return .notUsed
        }
    }
    
    public func startDemo(_ item: SI, started: (() -> Void)? = nil, ended: (() -> Void)? = nil) {
        guard let time: TimeInterval = item.demoTime else {
            print("Store Manager - Start Demo - No valid demo time for item:", item.productID)
            return
        }
        guard keychain.getData(item.keychainDemoDateKey) == nil else {
            print("Store Manager - Start Demo - Already started demo for item:", item.productID)
            return
        }
        let startDate: Date = .now
        let info = DemoInfo(state: .ongoing, startDate: startDate)
        do {
            let data: Data = try jsonDateEncoder.encode(startDate)
            keychain.set(data, forKey: item.keychainDemoDateKey)
            demoIfNeeded(item, started: started, ended: ended)
        } catch {
            print("Store Manager - Start Demo - Error encoding start date for item:", item.productID)
        }
    }
    
    private func demoIfNeeded(_ item: SI, started: (() -> Void)? = nil, ended: (() -> Void)? = nil) {
        guard let time: TimeInterval = item.demoTime else { return }
        let info = demoInfo(item)
        guard info.state == .ongoing else { return }
        guard let startDate = info.startDate else { return }
        guard (Date.now.advanced(by: -time)...Date.now).contains(startDate) else { return }
        demoStarted(item)
        started?()
        let timer = Timer(fire: startDate.advanced(by: time), interval: 0.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.demoEnded(item)
                ended?()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
    }
    
    private func demoStarted(_ item: SI) {
        demoingItems.insert(item)
    }
    
    private func demoEnded(_ item: SI) {
        demoingItems.remove(item)
    }
    
#if DEBUG
    /// Debug mode only
    public func debugResetAllDemos() {
        for item in SI.allCases {
            demoEnded(item)
            keychain.delete(item.keychainDemoDateKey)
        }
    }
#endif
}
