//
//  AsyncLock.swift
//  SwiftOBD2
//
//  The ELM327 handles one request at a time. Without this, two callers
//  (say, the live gauges and the drive logger) could interleave writes and
//  read each other's responses, or a mode 01 poll could go out while a
//  manufacturer read has the header pointed at one ECU.
//

import Foundation

actor AsyncLock {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            locked = false
        } else {
            // Hand the lock straight to the next waiter; it stays locked.
            waiters.removeFirst().resume()
        }
    }

    /// Runs `body` while holding the lock, releasing it even if `body` throws.
    nonisolated func withLock<T>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let result = try await body()
            await release()
            return result
        } catch {
            await release()
            throw error
        }
    }
}
