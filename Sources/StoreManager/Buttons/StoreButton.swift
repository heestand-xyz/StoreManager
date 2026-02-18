import SwiftUI
import StoreKit

public struct StoreButton<Item: StoreItem, Label: View>: View {
    
    let item: Item
    let storeManager: StoreManager<Item>
    let label: Label
    @Binding var purchasing: Bool
    let completion: (Result<StoreManager<Item>.PurchaseCompletion, Error>) -> ()
    
    public init(for item: Item, 
                storeManager: StoreManager<Item>,
                purchasing: Binding<Bool>,
                completion: @escaping (Result<StoreManager<Item>.PurchaseCompletion, Error>) -> (),
                label: () -> Label) {
        self.item = item
        self.storeManager = storeManager
        self.label = label()
        _purchasing = purchasing
        self.completion = completion
    }
    
#if os(visionOS)
    @Environment(\.purchase) private var purchase: PurchaseAction
#endif
    
    public var body: some View {
        Button {
            Task { @MainActor in
                purchasing = true
                do {
                    guard let product = storeManager.products[item] else {
                        throw StoreManager<Item>.StoreError.productNotFound(id: item.productID)
                    }
#if os(visionOS)
                    let result: Product.PurchaseResult = try await purchase(product)
#else
                    let result: Product.PurchaseResult = try await product.purchase()
#endif
                    let purchaseCompletion: StoreManager.PurchaseCompletion = try await storeManager.processPurchase(result: result, for: item)
                    completion(.success(purchaseCompletion))
                } catch {
                    completion(.failure(error))
                }
                purchasing = false
            }
        } label: {
            label
        }
        .disabled(purchasing)
    }
}
