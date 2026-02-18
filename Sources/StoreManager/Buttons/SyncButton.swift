import SwiftUI
import StoreKit

public struct SyncButton<Item: StoreItem, Label: View>: View {
    
    let storeManager: StoreManager<Item>
    let label: Label
    @Binding var syncing: Bool
    @Binding var failure: Error?
    
    public init(
        storeManager: StoreManager<Item>,
        syncing: Binding<Bool>,
        failure: Binding<Error?>,
        label: () -> Label
    ) {
        self.storeManager = storeManager
        self.label = label()
        _syncing = syncing
        _failure = failure
    }
    
#if os(visionOS)
    @Environment(\.purchase) private var purchase: PurchaseAction
#endif
    
    public var body: some View {
        Button {
            syncing = true
            failure = nil
            Task {
                do {
                    try await storeManager.sync()
                } catch {
                    failure = error
                }
                syncing = false
            }
        } label: {
            label
        }
        .disabled(syncing)
    }
}
