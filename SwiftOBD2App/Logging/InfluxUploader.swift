//
//  InfluxUploader.swift
//  SwiftOBD2App
//
//  Uploads buffered drives to InfluxDB v2 when the phone is on Wi-Fi.
//  Nothing on the homelab needs to be exposed to the internet: the phone
//  pushes to InfluxDB on the LAN once it's home. (A Tailscale address works
//  too if you ever want uploads away from home; it's optional.)
//
//  Use an InfluxDB token that can only write to the one bucket.
//

import Foundation
import Network

struct InfluxConfig: Equatable {
    var url: String      // e.g. https://influx.example.com or http://192.168.1.19:8086
    var org: String
    var bucket: String
    var token: String

    static let defaultsKey = "influxConfig"

    static func load() -> InfluxConfig {
        let d = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        return InfluxConfig(url: d["url"] ?? "", org: d["org"] ?? "", bucket: d["bucket"] ?? "obd",
                            token: Keychain.get(account: "token") ?? "")
    }

    func save() {
        UserDefaults.standard.set(["url": url, "org": org, "bucket": bucket], forKey: Self.defaultsKey)
        Keychain.set(token, account: "token")
    }

    var isComplete: Bool { !url.isEmpty && !org.isEmpty && !bucket.isEmpty && !token.isEmpty }

    /// Builds the write URL, refusing to send the token in cleartext except to
    /// a private LAN address or a .local name.
    func writeURL() throws -> URL {
        guard var components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            throw InfluxError.badURL
        }
        if scheme == "http" && !Self.isPrivate(host) {
            throw InfluxError.cleartextToPublicHost
        }
        guard scheme == "http" || scheme == "https" else { throw InfluxError.badURL }
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path)
            + "/api/v2/write"
        components.queryItems = [
            URLQueryItem(name: "org", value: org),
            URLQueryItem(name: "bucket", value: bucket),
            URLQueryItem(name: "precision", value: "s"),
        ]
        guard let result = components.url else { throw InfluxError.badURL }
        return result
    }

    static func isPrivate(_ host: String) -> Bool {
        if host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168): return true
        case (172, 16...31): return true
        case (100, 64...127): return true // Tailscale / CGNAT range
        default: return false
        }
    }
}

enum InfluxError: LocalizedError {
    case badURL, cleartextToPublicHost, notConfigured
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "The InfluxDB address isn't a valid http(s) URL."
        case .cleartextToPublicHost: return "Use https for anything that isn't a LAN or Tailscale address."
        case .notConfigured: return "Fill in the InfluxDB settings first."
        case let .server(code, body): return "InfluxDB answered \(code): \(body)"
        }
    }
}

@MainActor
final class InfluxUploader: ObservableObject {
    static let shared = InfluxUploader()

    @Published private(set) var status = "Nothing uploaded yet"
    @Published private(set) var onWiFi = false

    private let monitor = NWPathMonitor()
    private var uploading = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.status == .satisfied && path.usesInterfaceType(.wifi) && !path.isExpensive
            Task { @MainActor in
                guard let self else { return }
                let cameOnline = wifi && !self.onWiFi
                self.onWiFi = wifi
                if cameOnline {
                    await self.uploadPendingIfAllowed(reason: "joined Wi-Fi")
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "InfluxUploader.path"))
    }

    /// Automatic uploads only happen on Wi-Fi.
    func uploadPendingIfAllowed(reason: String) async {
        guard onWiFi else {
            status = "Waiting for Wi-Fi to upload"
            return
        }
        await uploadPending()
    }

    /// Uploads every buffered drive; deletes each file only after InfluxDB accepts it.
    func uploadPending() async {
        guard !uploading else { return }
        uploading = true
        defer { uploading = false }

        let config = InfluxConfig.load()
        guard config.isComplete else {
            status = InfluxError.notConfigured.localizedDescription
            return
        }

        let files = await DriveLogStore.shared.pendingFiles()
        guard !files.isEmpty else {
            status = "All drives uploaded"
            return
        }

        var sent = 0
        for file in files {
            do {
                try await upload(file, config: config)
                await DriveLogStore.shared.remove(file)
                sent += 1
            } catch {
                status = "Upload failed: \(error.localizedDescription)"
                return
            }
        }
        status = "Uploaded \(sent) drive\(sent == 1 ? "" : "s")"
    }

    private func upload(_ file: URL, config: InfluxConfig) async throws {
        var request = URLRequest(url: try config.writeURL())
        request.httpMethod = "POST"
        request.setValue("Token \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: file)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 204 else {
            throw InfluxError.server(code, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
    }
}
