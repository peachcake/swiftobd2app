//
//  DriveActivityAttributes.swift
//  Shared by the app and DriveActivityExtension.
//
//  The Live Activity is how the truck's temps reach CarPlay: on iOS 26 the
//  CarPlay dashboard shows Live Activities (small family) without a CarPlay
//  app entitlement. Apple's CarPlay app rules forbid real-time engine data
//  and refreshes faster than every 10 s, so we don't build a CarPlay app.
//

import ActivityKit
import Foundation

struct DriveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var atfPanF: Double?
        var coolantF: Double?
        var level: TempLevel
        var updatedAt: Date
    }

    var vehicleName: String
}

enum TempLevel: String, Codable, Hashable {
    case normal, warm, hot

    /// Thresholds for transmission fluid, °F. Starting guesses, not Toyota specs:
    /// owners commonly treat ~200 as warm and 240+ as time to back off.
    static func forATF(_ f: Double?) -> TempLevel {
        guard let f else { return .normal }
        if f >= 240 { return .hot }
        if f >= 210 { return .warm }
        return .normal
    }
}
