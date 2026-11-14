//
//  CommandGate.swift
//  SwiftOBD2
//
//  Read-only allowlist for everything sent to the ELM327/STN adapter.
//
//  Every command must pass `CommandGate.check(_:)` before it is written to the
//  adapter. Anything not explicitly allowed is refused: there is no blocklist
//  to keep current. That keeps out, among others:
//    - OBD mode 04 (clear DTCs and freeze frame data) and mode 08 (control)
//    - UDS/KWP services: 10 session control, 11 ECU reset, 14 clear DTCs,
//      27 security access, 28 comm control, 2E write DID, 2F/30 I/O control,
//      31 routine control, 34-37 download/upload, 3B/3D write, 85 DTC setting
//    - adapter commands that write EEPROM (AT PP), change baud (AT BRD),
//      put frames on the bus by themselves (AT WM, AT FI, AT SW) or use the
//      STN extended set (ST..), which can send raw frames
//    - line breaks or control characters, because the ELM327 runs every
//      CR-terminated line it receives: "0100\r04" would otherwise smuggle a
//      second command through one write.
//

import Foundation

public enum CommandGateError: Error, Equatable, LocalizedError {
    case blocked(command: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .blocked(command, reason):
            return "Blocked command \"\(command)\": \(reason)"
        }
    }
}

public enum CommandGate {
    /// Request headers the adapter may address. 7DF is the OBD functional
    /// (broadcast) address, 7E0 the engine ECU, 7E1 the transmission ECU.
    public static let allowedHeaders: Set<String> = ["7DF", "7E0", "7E1"]

    /// Manufacturer-specific reads, matched exactly (service byte + PID).
    /// Toyota 21 82: automatic transmission fluid temperatures.
    public static let allowedManufacturerReads: Set<String> = ["2182"]

    /// AT commands allowed verbatim (after removing spaces and uppercasing).
    static let allowedATCommands: Set<String> = [
        "ATZ",      // reset adapter (adapter only)
        "ATD",      // adapter defaults (adapter only)
        "ATI",      // adapter version
        "ATE0",     // echo off
        "ATL0",     // linefeeds off
        "ATS0",     // spaces off
        "ATH0", "ATH1", // headers off/on
        "ATDP", "ATDPN", // describe protocol
        "ATRV",     // read battery voltage
        "ATAT0", "ATAT1", "ATAT2", // adaptive timing
    ]

    /// Maximum PIDs in one mode 01 request (the ELM327 limit on CAN).
    static let maxMode1PIDs = 6

    /// Checks a command and returns it normalized (uppercase, no spaces).
    /// Throws `CommandGateError.blocked` for anything not on the allowlist.
    @discardableResult
    public static func check(_ raw: String) throws -> String {
        func block(_ reason: String) -> CommandGateError {
            .blocked(command: printable(raw), reason: reason)
        }

        // Printable ASCII only. Rejects CR, LF, tabs, NUL and anything non-ASCII.
        guard raw.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E }) else {
            throw block("control or non-ASCII characters are not allowed")
        }

        let cmd = raw.replacingOccurrences(of: " ", with: "").uppercased()
        guard !cmd.isEmpty else { throw block("empty command") }
        guard cmd.unicodeScalars.allSatisfy({ isUpperAlnum($0) || $0 == "@" }) else {
            throw block("unexpected characters")
        }

        if cmd.hasPrefix("AT") {
            try checkAT(cmd, block)
            return cmd
        }
        if cmd.hasPrefix("ST") {
            throw block("STN extended commands are not allowed")
        }
        try checkOBD(cmd, block)
        return cmd
    }

    public static func isAllowed(_ raw: String) -> Bool {
        (try? check(raw)) != nil
    }

    // MARK: - AT commands

    private static func checkAT(_ cmd: String, _ block: (String) -> CommandGateError) throws {
        if allowedATCommands.contains(cmd) { return }

        // ATSP<n>: select protocol 0-C (0 = automatic). Adapter setting only.
        if cmd.hasPrefix("ATSP") {
            let arg = cmd.dropFirst(4)
            if arg.count == 1, let c = arg.first, "0123456789ABC".contains(c) { return }
            throw block("unknown protocol")
        }

        // ATST<hh>: response timeout. Adapter setting only.
        if cmd.hasPrefix("ATST") {
            let arg = cmd.dropFirst(4)
            if arg.count == 2, arg.allSatisfy(\.isHexDigit) { return }
            throw block("bad timeout value")
        }

        // ATSH<hhh>: request header. Only known read targets.
        if cmd.hasPrefix("ATSH") {
            let header = String(cmd.dropFirst(4))
            if allowedHeaders.contains(header) { return }
            throw block("header \(header) is not on the allowlist")
        }

        throw block("AT command is not on the allowlist")
    }

    // MARK: - OBD requests

    private static func checkOBD(_ cmd: String, _ block: (String) -> CommandGateError) throws {
        guard cmd.allSatisfy(\.isHexDigit) else { throw block("request must be hex") }
        // Odd lengths include the ELM "response count" suffix (e.g. "0100 1"),
        // which we don't use.
        guard cmd.count % 2 == 0 else { throw block("request must be whole bytes") }

        let service = String(cmd.prefix(2))
        let payloadBytes = (cmd.count - 2) / 2

        switch service {
        case "01": // current data
            guard (1...maxMode1PIDs).contains(payloadBytes) else {
                throw block("mode 01 takes 1-\(maxMode1PIDs) PIDs")
            }
        case "03", "07", "0A": // stored, pending and permanent DTCs
            guard payloadBytes == 0 else { throw block("mode \(service) takes no data") }
        case "06": // on-board monitor test results
            guard payloadBytes == 1 else { throw block("mode 06 takes one MID") }
        case "09": // vehicle info (VIN, calibration IDs)
            guard payloadBytes == 1 else { throw block("mode 09 takes one PID") }
        default:
            guard allowedManufacturerReads.contains(cmd) else {
                throw block("service \(service) is not on the allowlist")
            }
        }
    }

    // MARK: - Helpers

    private static func isUpperAlnum(_ s: Unicode.Scalar) -> Bool {
        (s.value >= 0x30 && s.value <= 0x39) || (s.value >= 0x41 && s.value <= 0x5A)
    }

    /// Escapes control characters so blocked commands log safely.
    static func printable(_ raw: String) -> String {
        raw.unicodeScalars.map { s in
            (s.value >= 0x20 && s.value <= 0x7E) ? String(s) : String(format: "\\x%02X", s.value)
        }.joined()
    }
}
