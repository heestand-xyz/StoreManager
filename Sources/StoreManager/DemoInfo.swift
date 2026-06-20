//
//  DemoInfo.swift
//  StoreManager
//
//  Created by Anton Heestand on 2026-06-20.
//

import Foundation

public struct DemoInfo: Codable, Sendable {
    public let state: DemoState
    public let startDate: Date?
}

extension DemoInfo {
    static let notUsed = DemoInfo(state: .notUsed, startDate: nil)
}

extension DemoInfo {
    public func timeRange<SI: StoreItem>(for item: SI) -> Range<Date>? {
        let time: TimeInterval = item.demoTime ?? 0.0
        switch state {
        case .notUsed:
            return nil
        case .ongoing:
            guard let startDate else { return nil }
            return startDate..<startDate.advanced(by: time)
        case .used:
            return nil
        }
    }
    
    public func timeRemaining<SI: StoreItem>(for item: SI) -> TimeInterval {
        let time: TimeInterval = item.demoTime ?? 0.0
        switch state {
        case .notUsed:
            return time
        case .ongoing:
            guard let startDate else { return time }
            return max(0.0, min(time, time - startDate.distance(to: .now)))
        case .used:
            return 0.0
        }
    }
}
