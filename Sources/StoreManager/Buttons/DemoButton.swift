import SwiftUI
import StoreKit

public struct DemoButton<
    Item: StoreItem,
    NotUsedLabel: View,
    OngoingLabel: View,
    UsedLabel: View
>: View {
    
    let item: Item
    let storeManager: StoreManager<Item>
    let notUsedLabel: (AnyView) -> NotUsedLabel
    let ongoingLabel: (AnyView) -> OngoingLabel
    let usedLabel: (AnyView) -> UsedLabel
    
    @State private var info: DemoInfo = .notUsed
    
    public init(
        for item: Item,
        storeManager: StoreManager<Item>,
        notUsedLabel: @escaping (AnyView) -> NotUsedLabel,
        ongoingLabel: @escaping (AnyView) -> OngoingLabel,
        usedLabel: @escaping (AnyView) -> UsedLabel,
    ) {
        self.item = item
        self.storeManager = storeManager
        self.notUsedLabel = notUsedLabel
        self.ongoingLabel = ongoingLabel
        self.usedLabel = usedLabel
    }
    
    public var body: some View {
        ZStack {
            switch info.state {
            case .notUsed:
                Button {
                    start()
                } label: {
                    notUsedLabel(AnyView(Group {
                        if let time = item.demoTime {
                            if time.truncatingRemainder(dividingBy: 60 * 60) == 0.0 {
                                let hours = Int(time / (60 * 60))
                                Text("Demo for \(hours) hour\(hours > 1 ? "s" : "")")
                            } else if time.truncatingRemainder(dividingBy: 60) == 0.0 {
                                let minutes = Int(time / (60))
                                Text("Demo for \(minutes) minute\(minutes > 1 ? "s" : "")")
                            } else {
                                Text("Demo for a duration of \((Date.now..<Date.now.advanced(by: time)), format: .timeDuration)")
                            }
                        }
                    }))
                }
            case .ongoing:
                TimelineView(.animation) { context in
                    ongoingLabel(AnyView(Group {
                        if let timeRange: Range<Date> = info.timeRange(for: item), context.date < timeRange.upperBound {
                            Text("Demo time: \(context.date..<timeRange.upperBound, format: .timeDuration)")
                                .monospacedDigit()
                        } else {
                            Text("Demo time...")
                        }
                    }))
                }
            case .used:
                usedLabel(AnyView(Group {
                    Text("Demo time expired.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }))
            }
        }
        .onAppear {
            info = storeManager.demoInfo(item)
        }
    }
    
    private func start() {
        storeManager.startDemo(
            item,
            started: {
                info = storeManager.demoInfo(item)
            },
            ended: {
                info = storeManager.demoInfo(item)
            }
        )
    }
}
