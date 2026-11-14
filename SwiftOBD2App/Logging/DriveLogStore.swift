//
//  DriveLogStore.swift
//  SwiftOBD2App
//
//  Buffers each drive on the phone as a line-protocol file until it has been
//  uploaded, so nothing is lost when you're out of range of home.
//

import Foundation

actor DriveLogStore {
    static let shared = DriveLogStore()

    let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("PendingDrives", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func append(_ line: String, driveID: String) {
        let url = directory.appendingPathComponent("\(driveID).lp")
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func pendingFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                    includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "lp" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func pendingSummary() -> (drives: Int, bytes: Int) {
        let files = pendingFiles()
        let bytes = files.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return (files.count, bytes)
    }
}
