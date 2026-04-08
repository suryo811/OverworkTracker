import Foundation
import GRDB
import AppKit

final class DatabaseManager: Sendable {
    private let dbQueue: DatabaseQueue
    private nonisolated(unsafe) let iconCache = NSCache<NSString, NSImage>()

    init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("OverworkTracker", isDirectory: true)

        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let dbPath = appSupport.appendingPathComponent("tracker.sqlite").path
        dbQueue = try DatabaseQueue(path: dbPath)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_tracking_session") { db in
            try db.create(table: "tracking_session") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("appName", .text).notNull()
                t.column("bundleID", .text)
                t.column("windowTitle", .text)
                t.column("startTime", .double).notNull()
                t.column("duration", .double).notNull()
                t.column("endTime", .double).notNull()
            }

            try db.create(
                index: "idx_session_start_time",
                on: "tracking_session",
                columns: ["startTime"]
            )
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Write Operations

    func insertSession(_ session: TrackingSession) throws -> Int64 {
        try dbQueue.write { db in
            try session.insert(db)
            return db.lastInsertedRowID
        }
    }

    func updateSessionDuration(id: Int64, duration: TimeInterval, endTime: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE tracking_session
                    SET duration = ?, endTime = ?
                    WHERE id = ?
                    """,
                arguments: [duration, endTime, id]
            )
        }
    }

    // MARK: - Read Operations

    func fetchSummaries(for date: Date) throws -> [AppUsageSummary] {
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

        let rows = try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT appName, bundleID, SUM(duration) as totalDuration,
                           GROUP_CONCAT(DISTINCT windowTitle) as windowTitles
                    FROM tracking_session
                    WHERE startTime >= ? AND startTime < ?
                    GROUP BY COALESCE(bundleID, appName)
                    ORDER BY totalDuration DESC
                    """,
                arguments: [dayStart, dayEnd]
            )
        }

        return rows.map { row in
            let bundleID: String? = row["bundleID"]
            let appName: String = row["appName"]
            let totalDuration: TimeInterval = row["totalDuration"]
            let windowTitles: [String] = (row["windowTitles"] as String?)
                .map { $0.split(separator: ",").map(String.init) } ?? []

            let icon = appIcon(for: bundleID)

            return AppUsageSummary(
                id: bundleID ?? appName,
                appName: appName,
                bundleID: bundleID,
                totalDuration: totalDuration,
                icon: icon,
                windowTitles: windowTitles
            )
        }
    }

    func fetchTotalTime(for date: Date) throws -> TimeInterval {
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

        return try dbQueue.read { db in
            let total = try Double.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(duration), 0)
                    FROM tracking_session
                    WHERE startTime >= ? AND startTime < ?
                    """,
                arguments: [dayStart, dayEnd]
            )
            return total ?? 0
        }
    }

    // MARK: - Helpers

    private func appIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        let key = bundleID as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache.setObject(icon, forKey: key)
        return icon
    }
}
