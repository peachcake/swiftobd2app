//
//  ToyotaATF.swift
//  SwiftOBD2App
//
//  Toyota automatic transmission fluid temperature, read with mode 21 PID 82.
//
//  UNVERIFIED ON A 2024 4RUNNER. Sources are owner forums, not Toyota:
//   - ClubLexus GX460 thread "Anyone pulling transmission temps via OBD":
//     21 82, pan = ((A*256+B)*7/100 - 400)/10, converter = same on C,D
//   - IH8MUD "Anyone know the PID for trans temp?": 7E0 + 2182 confirmed on a
//     2013 Land Cruiser; 7E1 returned no data there
//   - TacomaWorld "Transmission fluid temperature PIDs": same formula, units F;
//     a 2014 4Runner owner says it "looks like the same pid" (not confirmed)
//  The forum posts label the formula's output as °F, and the readings people
//  report (170-180 at warm idle) only make sense in °F. Treat that as likely,
//  not certain: every reading also logs the raw bytes so it can be recomputed.
//

import Foundation

struct ToyotaATF: Equatable {
    /// ECUs to try, in order. The 1GR/A750 4Runner's transmission logic lives
    /// in the engine ECU, so 7E0 is the likely target; 7E1 is the fallback.
    static let headers = ["7E0", "7E1"]
    static let request = "2182"
    static let pid: UInt8 = 0x82

    /// nil when the decoded value is implausible (wrong formula or bytes).
    let panF: Double?
    let converterF: Double?
    /// Response payload after the PID echo, as hex, for recalibration later.
    let rawHex: String

    var panC: Double? { panF.map { ($0 - 32) * 5 / 9 } }
    var converterC: Double? { converterF.map { ($0 - 32) * 5 / 9 } }

    /// Plausible range for transmission fluid in °F. Anything outside means the
    /// formula, units or bytes are wrong for this truck, not that it's -40.
    static let plausibleF: ClosedRange<Double> = -40...330

    /// `payload` starts at the echoed PID byte: [0x82, A, B, C, D, ...].
    init?(payload: Data) {
        let bytes = [UInt8](payload)
        guard bytes.count >= 3, bytes[0] == Self.pid else { return nil }
        let data = Array(bytes.dropFirst())

        panF = Self.temp(data, 0, 1)
        converterF = Self.temp(data, 2, 3)
        rawHex = data.map { String(format: "%02X", $0) }.joined()
    }

    /// Forum formula: ((hi*256 + lo) * 7/100 - 400) / 10, in °F.
    static func temp(_ data: [UInt8], _ hi: Int, _ lo: Int) -> Double? {
        guard data.count > lo else { return nil }
        let raw = Double(Int(data[hi]) << 8 | Int(data[lo]))
        let value = (raw * 7 / 100 - 400) / 10
        return plausibleF.contains(value) ? value : nil
    }
}
