//
//  DriveActivityWidget.swift
//  DriveActivityExtension
//
//  Live Activity UI. The `.small` supplemental family is what the CarPlay
//  dashboard (iOS 26) and Apple Watch Smart Stack use.
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DriveActivityBundle: WidgetBundle {
    var body: some Widget {
        DriveLiveActivity()
    }
}

struct DriveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            LockScreenView(state: context.state, stale: context.isStale)
                .padding()
                .activityBackgroundTint(.black.opacity(0.7))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Reading(label: "ATF", value: context.state.atfPanF, level: context.state.level)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Reading(label: "Coolant", value: context.state.coolantF, level: .normal)
                }
            } compactLeading: {
                Text("ATF")
            } compactTrailing: {
                Text(Format.temp(context.state.atfPanF))
                    .foregroundStyle(context.state.level.color)
            } minimal: {
                Text(Format.temp(context.state.atfPanF))
                    .foregroundStyle(context.state.level.color)
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

/// Lock screen, and the small family on CarPlay/Watch.
struct LockScreenView: View {
    let state: DriveActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        HStack(spacing: 24) {
            Reading(label: "ATF", value: state.atfPanF, level: state.level)
            Reading(label: "Coolant", value: state.coolantF, level: .normal)
        }
        .opacity(stale ? 0.5 : 1)
        .overlay(alignment: .topTrailing) {
            if stale {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.caption)
            }
        }
    }
}

struct Reading: View {
    let label: String
    let value: Double?
    let level: TempLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Format.temp(value))
                .font(.title2.monospacedDigit().bold())
                .foregroundStyle(level.color)
        }
    }
}

enum Format {
    static func temp(_ f: Double?) -> String {
        guard let f else { return "--" }
        return "\(Int(f.rounded()))°"
    }
}

extension TempLevel {
    var color: Color {
        switch self {
        case .normal: return .primary
        case .warm: return .orange
        case .hot: return .red
        }
    }
}
