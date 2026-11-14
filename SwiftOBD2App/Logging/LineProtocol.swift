//
//  LineProtocol.swift
//  SwiftOBD2App
//
//  Minimal InfluxDB line protocol writer.
//  https://docs.influxdata.com/influxdb/v2/reference/syntax/line-protocol/
//

import Foundation

enum InfluxField: Equatable {
    case float(Double)
    case int(Int)
    case string(String)
}

enum LineProtocol {
    /// `measurement,tag=v field=1.0,field2="x" <unix seconds>`
    static func line(measurement: String,
                     tags: [String: String],
                     fields: [String: InfluxField],
                     time: Date) -> String {
        var head = escapeMeasurement(measurement)
        for key in tags.keys.sorted() {
            guard let value = tags[key], !value.isEmpty else { continue }
            head += ",\(escapeKey(key))=\(escapeKey(value))"
        }

        let body = fields.keys.sorted().compactMap { key -> String? in
            guard let field = fields[key] else { return nil }
            switch field {
            case let .float(v):
                guard v.isFinite else { return nil }
                return "\(escapeKey(key))=\(v)"
            case let .int(v):
                return "\(escapeKey(key))=\(v)i"
            case let .string(v):
                return "\(escapeKey(key))=\"\(escapeString(v))\""
            }
        }.joined(separator: ",")

        return "\(head) \(body) \(Int(time.timeIntervalSince1970))"
    }

    private static func escapeMeasurement(_ s: String) -> String {
        s.replacingOccurrences(of: ",", with: "\\,")
         .replacingOccurrences(of: " ", with: "\\ ")
    }

    /// Tag keys, tag values and field keys escape commas, equals signs and spaces.
    private static func escapeKey(_ s: String) -> String {
        escapeMeasurement(s).replacingOccurrences(of: "=", with: "\\=")
    }

    private static func escapeString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
