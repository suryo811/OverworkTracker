import Foundation
import GRDB
import AppKit

final class DatabaseManager: Sendable {
    private let dbQueue: DatabaseQueue

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

    func fetchTodaySummaries() throws -> [AppUsageSummary] {
        let todayStart = Calendar.current.startOfDay(for: Date())

        let rows = try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT appName, bundleID, SUM(duration) as totalDuration
                    FROM tracking_session
                    WHERE startTime >= ?
                    GROUP BY COALESCE(bundleID, appName)
                    ORDER BY totalDuration DESC
                    """,
                arguments: [todayStart]
            )
        }

        return rows.map { row in
            let bundleID: String? = row["bundleID"]
            let appName: String = row["appName"]
            let totalDuration: TimeInterval = row["totalDuration"]

            let icon = appIcon(for: bundleID)

            return AppUsageSummary(
                id: bundleID ?? appName,
                appName: appName,
                bundleID: bundleID,
                totalDuration: totalDuration,
                icon: icon
            )
        }
    }

    func fetchTotalHoursToday() throws -> TimeInterval {
        let todayStart = Calendar.current.startOfDay(for: Date())

        return try dbQueue.read { db in
            let total = try Double.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(duration), 0)
                    FROM tracking_session
                    WHERE startTime >= ?
                    """,
                arguments: [todayStart]
            )
            return total ?? 0
        }
    }

    // MARK: - Helpers

    private func appIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
