import Foundation
import GRDB

struct TrackingSession: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var appName: String
    var bundleID: String?
    var windowTitle: String?
    var startTime: Date
    var duration: TimeInterval
    var endTime: Date

    static let databaseTableName = "tracking_session"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let appName = Column(CodingKeys.appName)
        static let bundleID = Column(CodingKeys.bundleID)
        static let windowTitle = Column(CodingKeys.windowTitle)
        static let startTime = Column(CodingKeys.startTime)
        static let duration = Column(CodingKeys.duration)
        static let endTime = Column(CodingKeys.endTime)
    }
}
