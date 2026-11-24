import Foundation
import SQLite3

struct Row {
    let values: [String: Any]

    func string(_ key: String) -> String? { values[key] as? String }
    func int(_ key: String) -> Int? {
        if let v = values[key] as? Int64 { return Int(v) }
        if let v = values[key] as? Double { return Int(v) }
        return nil
    }
    func double(_ key: String) -> Double? {
        if let v = values[key] as? Double { return v }
        if let v = values[key] as? Int64 { return Double(v) }
        return nil
    }
}

/// Read-only access to the `wissen` database. Writing is always done by the CLI.
final class Database {
    private var handle: OpaquePointer?

    init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit { sqlite3_close(handle) }

    func query(_ sql: String) -> [Row] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [Row] = []
        let count = sqlite3_column_count(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            var values: [String: Any] = [:]
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: values[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT: values[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: values[name] = String(cString: sqlite3_column_text(stmt, i))
                default: break
                }
            }
            rows.append(Row(values: values))
        }
        return rows
    }
}
