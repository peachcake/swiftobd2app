//
//  DriveView.swift
//  SwiftOBD2App
//
//  Start/stop a logged drive and watch ATF and coolant temps.
//

import SwiftUI
import SwiftOBD2

struct DriveView: View {
    @EnvironmentObject var obdService: OBDService
    @EnvironmentObject var monitor: DriveMonitor
    @ObservedObject private var uploader = InfluxUploader.shared
    @State private var pending = (drives: 0, bytes: 0)

    var body: some View {
        List {
            Section("Transmission") {
                big("ATF pan", monitor.atf?.panF, level: TempLevel.forATF(monitor.atf?.panF))
                big("ATF converter", monitor.atf?.converterF, level: .normal)
                Text(monitor.atfStatus).font(.footnote).foregroundStyle(.secondary)
            }
            Section("Engine") {
                big("Coolant", monitor.coolantF, level: .normal)
                row("Speed", monitor.speedMph.map { "\(Int($0)) mph" })
                row("RPM", monitor.rpm.map { "\(Int($0))" })
                row("Load", monitor.loadPct.map { "\(Int($0))%" })
            }
            Section {
                Button(monitor.isRunning ? "Stop drive" : "Start drive") {
                    monitor.isRunning ? monitor.stop() : monitor.start(obd: obdService)
                }
                .disabled(!monitor.isRunning && obdService.connectionState != .connectedToVehicle)
                if monitor.isRunning {
                    row("Samples logged", "\(monitor.samples)")
                }
                if let error = monitor.lastError {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
            } footer: {
                Text("Read-only: the app can't clear codes or write to the truck. Keep the app open on a mount while driving; background polling hasn't been tested yet.")
            }
            Section("Upload to InfluxDB") {
                row("Waiting to upload", "\(pending.drives) drive\(pending.drives == 1 ? "" : "s")")
                Text(uploader.status).font(.footnote).foregroundStyle(.secondary)
                Button("Upload now") {
                    Task {
                        await uploader.uploadPending()
                        pending = await DriveLogStore.shared.pendingSummary()
                    }
                }
                NavigationLink("InfluxDB settings") { InfluxSettingsView() }
            }
        }
        .navigationTitle("Drive")
        .task { pending = await DriveLogStore.shared.pendingSummary() }
        .onChange(of: monitor.isRunning) { _ in
            Task { pending = await DriveLogStore.shared.pendingSummary() }
        }
    }

    private func big(_ label: String, _ f: Double?, level: TempLevel) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(f.map { "\(Int($0.rounded()))°F" } ?? "--")
                .font(.title2.monospacedDigit().bold())
                .foregroundStyle(level.color)
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value ?? "--").foregroundStyle(.secondary)
        }
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

struct InfluxSettingsView: View {
    @State private var config = InfluxConfig.load()
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("URL", text: $config.url, prompt: Text("https://influx.example.com"))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Organization", text: $config.org)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Bucket", text: $config.bucket)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Write-only token", text: $config.token)
            } footer: {
                Text("Create a token in InfluxDB that can only write to this bucket. It's kept in the Keychain. Plain http is only allowed to LAN, .local or Tailscale addresses. Drives upload automatically when the phone joins Wi-Fi.")
            }
            Section {
                Button("Save") {
                    do {
                        _ = try config.writeURL()
                        config.save()
                        message = "Saved"
                    } catch {
                        message = error.localizedDescription
                    }
                }
                if let message { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("InfluxDB")
    }
}
