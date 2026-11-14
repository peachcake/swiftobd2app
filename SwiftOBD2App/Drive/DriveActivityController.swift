//
//  DriveActivityController.swift
//  SwiftOBD2App
//
//  Starts, updates and ends the drive's Live Activity. iOS 26 shows it on the
//  CarPlay dashboard as well as the lock screen and Dynamic Island.
//

import ActivityKit
import Foundation

@MainActor
final class DriveActivityController {
    private var activity: Activity<DriveActivityAttributes>?

    func start(vehicleName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let initial = DriveActivityAttributes.ContentState(atfPanF: nil, coolantF: nil,
                                                           level: .normal, updatedAt: Date())
        activity = try? Activity.request(
            attributes: DriveActivityAttributes(vehicleName: vehicleName),
            content: .init(state: initial, staleDate: Date().addingTimeInterval(60)),
            pushType: nil
        )
    }

    /// `alert` buzzes and lights the screen; pass true only when ATF first turns hot.
    func update(_ state: DriveActivityAttributes.ContentState, alert shouldAlert: Bool) {
        guard let activity else { return }
        let alert: AlertConfiguration? = shouldAlert
            ? AlertConfiguration(title: "Transmission is hot",
                                 body: "ATF \(Int(state.atfPanF ?? 0))°F",
                                 sound: .default)
            : nil
        Task {
            // Marked stale after 60 s without an update, so a dropped adapter is obvious.
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(60)),
                                  alertConfiguration: alert)
        }
    }

    func end(finalState: DriveActivityAttributes.ContentState) {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(300)))
        }
    }
}
