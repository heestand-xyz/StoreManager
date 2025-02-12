import SwiftUI
import StoreKit

public struct RestoreButton<Item: StoreItem, Label: View>: View {
    
    let item: Item
    let storeManager: StoreManager<Item>
    let label: Label
    @Binding var restoring: Bool
    let completion: (Result<StoreManager<Item>.RestoreCompletion, Error>) -> ()
    
    public init(for item: Item,
                storeManager: StoreManager<Item>,
                restoring: Binding<Bool>,
                completion: @escaping (Result<StoreManager<Item>.RestoreCompletion, Error>) -> (),
                label: () -> Label) {
        self.item = item
        self.storeManager = storeManager
        self.label = label()
        _restoring = restoring
        self.completion = completion
    }
    
#if os(visionOS)
    @Environment(\.purchase) private var purchase: PurchaseAction
#endif
    
    public var body: some View {
        Button {
            Task {
                restoring = true
                do {
                    if storeManager.unlockedItems.contains(item) {
                        completion(.success(.alreadyAvailable))
                    } else {
                        try await storeManager.restore()
                        if storeManager.unlockedItems.contains(item) {
                            completion(.success(.restored))
                        } else {
                            completion(.success(.none))
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
                /// Fake sleep, it's too fast.
                try await Task.sleep(for: .seconds(1))
                restoring = false
            }
        } label: {
            label
        }
        .disabled(restoring)
    }
}
