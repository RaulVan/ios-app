import WCDBSwift

class MixinDatabase: BaseDatabase {

    private static let databaseVersion: Int = 6

    static let shared = MixinDatabase()

    private var _database = Database(withPath: MixinFile.databaseURL.path)
    override var database: Database! {
        get { return _database }
        set { }
    }

    func initDatabase(clearSentSenderKey: Bool = false) {
        _database = Database(withPath: MixinFile.databaseURL.path)
        do {
            try database.run(transaction: {
                var currentVersion = try database.getDatabaseVersion()
                if currentVersion == 0 {
                    currentVersion = DatabaseUserDefault.shared.mixinDatabaseVersion
                }
                try self.createBefore(database: database, currentVersion: currentVersion)

                try database.create(of: Asset.self)
                try database.create(table: Asset.topAssetsTableName, of: Asset.self)
                try database.create(of: Snapshot.self)
                try database.create(of: Sticker.self)
                try database.create(of: StickerRelationship.self)
                try database.create(of: Album.self)
                try database.create(of: MessageHistory.self)
                try database.create(of: SentSenderKey.self)
                try database.create(of: App.self)

                try database.create(of: User.self)
                try database.create(of: Conversation.self)
                try database.create(of: Message.self)
                try database.create(of: Participant.self)

                try database.create(of: Address.self)
                try database.create(of: Job.self)
                try database.create(of: ResendMessage.self)

                try self.createAfter(database: database, currentVersion: currentVersion)

                try database.prepareUpdateSQL(sql: MessageDAO.sqlTriggerLastMessageInsert).execute()
                try database.prepareUpdateSQL(sql: MessageDAO.sqlTriggerLastMessageDelete).execute()
                try database.prepareUpdateSQL(sql: MessageDAO.sqlTriggerUnseenMessageInsert).execute()

                if clearSentSenderKey {
                    try database.delete(fromTable: SentSenderKey.tableName)
                }
                try database.setDatabaseVersion(version: MixinDatabase.databaseVersion)
            })
        } catch let err as WCDBSwift.Error {
            UIApplication.traceWCDBError(err)
        } catch {
            UIApplication.traceError(error)
        }
    }

    private func createBefore(database: Database, currentVersion: Int) throws {
        guard currentVersion > 0 else {
            return
        }

        if currentVersion < 4 {
            try database.prepareUpdateSQL(sql: "DROP INDEX IF EXISTS messages_index1").execute()
            try database.prepareUpdateSQL(sql: "DROP INDEX IF EXISTS messages_index2").execute()
        }

        if currentVersion < 5 {
            try database.drop(table: Sticker.tableName)
            try database.drop(table: "sticker_albums")
        }

        if currentVersion < 6 {
            try database.prepareUpdateSQL(sql: "DROP INDEX IF EXISTS messages_status_index").execute()
            try database.prepareUpdateSQL(sql: "DROP TRIGGER IF EXISTS conversation_unseen_message_count_update").execute()
        }
    }

    private func createAfter(database: Database, currentVersion: Int) throws {
        guard currentVersion > 0 else {
            return
        }

        if currentVersion < 4, try database.isColumnExist(tableName: Snapshot.tableName, columnName: "counter_user_id") {
            try database.prepareUpdateSQL(sql: "UPDATE snapshots SET opponent_id = counter_user_id").execute()
        }
    }

    func logout() {
        do {
            try database.run(transaction: {
                try database.delete(fromTable: SentSenderKey.tableName)
            })
        } catch let err as WCDBSwift.Error {
            UIApplication.traceWCDBError(err)
        } catch {
            UIApplication.traceError(error)
        }
    }
    
}

extension MixinDatabase {
    
    class NullValue: ColumnEncodable {
        
        static var columnType: ColumnType {
            return .null
        }
        
        func archivedValue() -> FundamentalValue {
            return FundamentalValue(nil)
        }
        
    }

}
