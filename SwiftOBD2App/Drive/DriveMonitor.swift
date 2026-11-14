//
//  DriveMonitor.swift
//  SwiftOBD2App
//
//  Polls the truck during a drive, logs every sample, and keeps the Live
//  Activity (lock screen, Dynamic Island, CarPlay dashboard) current.
//  Every request goes through SwiftOBD2's CommandGate, so this can only read.
//

import Foundation
import SwiftOBD2

@MainActor
final class DriveMonitor: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var coolantF: Double?
    @Published private(set) var speedMph: Double?
    @Published private(set) var rpm: Double?
    @Published private(set) var loadPct: Double?
    @Published private(set) var atf: ToyotaATF?
    @Published private(set) var atfHeader: String?
    @Published private(set) var atfStatus = "Not read yet"
    @Published private(set) var lastError: String?
    @Published private(set) var samples = 0

    /// Standard PIDs polled every `fastInterval`.
    private let pids: [OBDCommand] = [.mode1(.coolantTemp), .mode1(.rpm), .mode1(.speed), .mode1(.engineLoad)]
    private let fastInterval: Duration = .seconds(1)
    private let atfEvery = 5          // read ATF every 5th tick
    private let activityEvery: TimeInterval = 10

    private var task: Task<Void, Never>?
    private var driveID = ""
    private let log = DriveLogStore.shared
    private let activity = DriveActivityController()
    private var lastActivityPush = Date.distantPast
    private var lastLevel: TempLevel = .normal

    var vehicleTag = "4runner"

    func start(obd: OBDService) {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        samples = 0
        driveID = Self.makeDriveID()
        activity.start(vehicleName: "4Runner")

        task = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollStandard(obd)
                if tick % self.atfEvery == 0 {
                    await self.pollATF(obd)
                }
                await self.record()
                self.pushActivityIfDue()
                tick += 1
                try? await Task.sleep(for: self.fastInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        activity.end(finalState: currentState())
        Task { await InfluxUploader.shared.uploadPendingIfAllowed(reason: "drive ended") }
    }

    // MARK: - Polling

    private func pollStandard(_ obd: OBDService) async {
        do {
            let results = try await obd.requestPIDs(pids, unit: .metric)
            coolantF = results[.mode1(.coolantTemp)].flatMap(Self.fahrenheit)
            speedMph = results[.mode1(.speed)].flatMap(Self.mph)
            rpm = results[.mode1(.rpm)]?.value
            loadPct = results[.mode1(.engineLoad)]?.value
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Tries 7E0 then 7E1 until one answers, then sticks with it.
    private func pollATF(_ obd: OBDService) async {
        let candidates = atfHeader.map { [$0] } ?? ToyotaATF.headers
        for header in candidates {
            do {
                guard let payload = try await obd.readManufacturer(header: header, request: ToyotaATF.request),
                      let reading = ToyotaATF(payload: payload) else {
                    continue
                }
                atf = reading
                atfHeader = header
                atfStatus = reading.panF == nil
                    ? "Got data from \(header), but the formula gives an implausible value (raw \(reading.rawHex))"
                    : "Reading from \(header)"
                return
            } catch {
                lastError = error.localizedDescription
            }
        }
        if atfHeader == nil {
            atfStatus = "No answer to 21 82 from 7E0 or 7E1"
        }
    }

    // MARK: - Logging

    private func record() async {
        var fields: [String: InfluxField] = [:]
        fields["coolant_f"] = coolantF.map(InfluxField.float)
        fields["speed_mph"] = speedMph.map(InfluxField.float)
        fields["rpm"] = rpm.map(InfluxField.float)
        fields["load_pct"] = loadPct.map(InfluxField.float)
        if let atf {
            fields["atf_pan_f"] = atf.panF.map(InfluxField.float)
            fields["atf_conv_f"] = atf.converterF.map(InfluxField.float)
            fields["atf_raw"] = .string(atf.rawHex)
        }
        guard !fields.isEmpty else { return }

        let line = LineProtocol.line(measurement: "drive",
                                     tags: ["vehicle": vehicleTag, "drive": driveID],
                                     fields: fields,
                                     time: Date())
        await log.append(line, driveID: driveID)
        samples += 1
    }

    // MARK: - Live Activity

    private func currentState() -> DriveActivityAttributes.ContentState {
        DriveActivityAttributes.ContentState(atfPanF: atf?.panF,
                                             coolantF: coolantF,
                                             level: TempLevel.forATF(atf?.panF),
                                             updatedAt: Date())
    }

    /// At most every 10 s, or right away when the ATF level changes.
    private func pushActivityIfDue() {
        let state = currentState()
        let due = Date().timeIntervalSince(lastActivityPush) >= activityEvery
        guard due || state.level != lastLevel else { return }
        activity.update(state, alert: state.level == .hot && lastLevel != .hot)
        lastActivityPush = Date()
        lastLevel = state.level
    }

    // MARK: - Helpers

    private static func fahrenheit(_ m: MeasurementResult) -> Double? {
        guard let unit = m.unit as? UnitTemperature else { return nil }
        return Measurement(value: m.value, unit: unit).converted(to: .fahrenheit).value
    }

    private static func mph(_ m: MeasurementResult) -> Double? {
        guard let unit = m.unit as? UnitSpeed else { return nil }
        return Measurement(value: m.value, unit: unit).converted(to: .milesPerHour).value
    }

    private static func makeDriveID() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
