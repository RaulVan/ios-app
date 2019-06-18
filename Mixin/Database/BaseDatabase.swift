import WCDBSwift

class BaseDatabase {

    internal var database: Database!
    private static var isTraced = false

    internal init() {
        trace()
        configure()
    }

    func configure(reset: Bool = false) {

    }

    func close() {
        database?.close()
    }

    func backup(path: String, progress: @escaping @convention (c) (Int32, Int32) -> Void) throws {
        try database.backup(withFile: path, progress: progress)
    }

    func trace() {
        guard !BaseDatabase.isTraced else {
            return
        }
        BaseDatabase.isTraced = true
        #if DEBUG
            Database.globalTrace(ofPerformance: { (tag, sqls, cost) in
                let millisecond = UInt64(cost) / NSEC_PER_MSEC
                if millisecond > 100 {
                    sqls.forEach({ (arg) in
                        print("[WCDB][Performance]SQL: \(arg.key)")
                    })
                    print("[WCDB][Performance]Total cost \(millisecond) ms")
                }
            })
        #endif

        Database.globalTrace(ofError: {(error) in
            switch error.type {
            case .warning, .sqliteGlobal:
                break
            default:
                FileManager.default.writeLog(log: "[WCDB][ERROR]\(error.description)", newSection: true)
                UIApplication.traceError(error)
            }
            #if DEBUG
            print("[WCDB][ERROR]\(error.description)")
            #endif
        })
    }

    func getStringValues(column: ColumnResultConvertible, tableName: String, condition: Condition? = nil, orderBy orderList: [OrderBy]? = nil, limit: Limit? = nil) -> [String] {
        let values = try! database.tryGetColumn(on: column, fromTable: tableName, where: condition, orderBy: orderList, limit: limit)
        return values.map { $0.stringValue }
    }

    func getInt32Values(column: ColumnResultConvertible, tableName: String, condition: Condition? = nil, orderBy orderList: [OrderBy]? = nil, limit: Limit? = nil) -> [Int32] {
        let values = try! database.tryGetColumn(on: column, fromTable: tableName, where: condition, orderBy: orderList, limit: limit)
        return values.map { $0.int32Value }
    }
    
    func getRowId(tableName: String, condition: Condition) -> Int64 {
        let sql = "SELECT ROWID FROM \(tableName) WHERE \(condition.asExpression())"
        return try! database.prepareSelectSQL(sql: sql, values: []).getValue().int64Value
    }
    
    func getDictionary(key: ColumnResult, value: ColumnResult, tableName: String, condition: Condition? = nil) -> [String: String] {
        let rows = try! database.tryGetRows(on: [key, value], fromTable: tableName, where: condition)
        var result = [String: String]()
        for row in rows {
            result[row[0].stringValue] = row[1].stringValue
        }
        return result
    }

    func isTableEmpty<T: BaseCodable>(type: T.Type) throws -> Bool {
        return try database.getValue(on: T.Properties.all[0], fromTable: T.tableName, limit: 1).type == .null
    }
    
    func isExist<T: BaseCodable>(type: T.Type, condition: Condition) -> Bool {
        return try! database.tryGetValue(on: type.Properties.all[0].asColumn(), fromTable: type.tableName, where: condition).type != .null
    }
    
    func getCodables<T: TableDecodable>(on propertyConvertibleList: [PropertyConvertible] = T.Properties.all, sql: String, values: [ColumnEncodable] = []) -> [T] {
        return try! database.execQuery(on: propertyConvertibleList, sql: sql, values: values).allObjects()
    }
    
    func getCodables<T: BaseCodable>(condition: Condition? = nil, orderBy orderList: [OrderBy]? = nil, limit: Limit? = nil) -> [T] {
        return try! database.tryGetObjects(on: T.Properties.all, fromTable: T.tableName, where: condition, orderBy: orderList, limit: limit)
    }
    
    func getCodables<T: Codable>(on propertyConvertibleList: [PropertyConvertible] = [], fromTable: String, condition: Condition? = nil, orderBy orderList: [OrderBy]? = nil, limit: Limit? = nil, callback: (FundamentalRowXColumn) -> [T]) -> [T] {
        return callback(try! database.tryGetRows(on: propertyConvertibleList, fromTable: fromTable, where: condition, orderBy: orderList, limit: limit))
    }
    
    func getCodables<T>(callback: (Database) throws -> [T]) -> [T] {
        do {
            return try callback(database)
        } catch {
            UIApplication.traceError(error)
        }
        return []
    }
    
    func getCodables<T: TableDecodable>(statement: StatementSelect) -> [T] {
        return try! database.getObjects(on: T.Properties.all, stmt: statement)
    }
    
    func getCodable<T: BaseCodable>(condition: Condition, orderBy orderList: [OrderBy]? = nil) -> T? {
        return try! database.tryGetObject(on: T.Properties.all, fromTable: T.tableName, where: condition, orderBy: orderList)
    }
    
    func scalar(on: ColumnResultConvertible, fromTable: String, condition: Condition? = nil, orderBy orderList: [OrderBy]? = nil) -> FundamentalValue? {
        let value = try! database.tryGetValue(on: on, fromTable: fromTable, where: condition, orderBy: orderList, limit: 1)
        return value.type == .null ? nil : value
    }
    
    func scalar(sql: String, values: [ColumnEncodable] = []) -> FundamentalValue {
        return try! database.prepareSelectSQL(sql: sql, values: values).getValue()
    }
    
    func getCount(on: ColumnResultConvertible, fromTable: String, condition: Condition? = nil) -> Int {
        return Int(try! database.tryGetValue(on: on, fromTable: fromTable, where: condition).int32Value)
    }
    
    @discardableResult
    func transaction(callback: (Database) throws -> Void) -> Bool {
        try! database.runTransaction {
            try callback(database)
        }
        return true
    }

    @discardableResult
    func update(maps: [(PropertyConvertible, ColumnEncodable?)], tableName: String, condition: Condition? = nil) -> Bool {
        try! database.runTransaction {
            try database.update(maps: maps, tableName: tableName, condition: condition)
        }
        return true
    }

    @discardableResult
    func insert<T: BaseCodable>(objects: [T], on propertyConvertibleList: [PropertyConvertible]? = nil) -> Bool {
        guard objects.count > 0 else {
            return true
        }
        try! database.runTransaction {
            try database.insert(objects: objects, on: propertyConvertibleList, intoTable: T.tableName)
        }
        return true
    }

    @discardableResult
    func insertOrReplace<T: BaseCodable>(objects: [T], on propertyConvertibleList: [PropertyConvertible]? = nil) -> Bool {
        guard objects.count > 0 else {
            return true
        }
        try! database.runTransaction {
            try database.insertOrReplace(objects: objects, on: propertyConvertibleList, intoTable: T.tableName)
        }
        return true
    }

    func deleteAll(table: String) {
        try! database.runTransaction {
            guard try database.isTableExists(table) else {
                return
            }
            try database.delete(fromTable: table)
        }
    }

    @discardableResult
    func delete(table: String, condition: Condition, cascadeDelete: Bool = false) -> Int {
        var result = 0
        try! database.runTransaction {
            if cascadeDelete {
                try database.exec(StatementPragma().pragma(Pragma.foreignKeys, to: true))
            }
            let delete = try database.prepareDelete(fromTable: table).where(condition)
            try delete.execute()
            result = delete.changes ?? 0
        }
        return result
    }
}

extension Database {

    func create<T: BaseCodable>(of rootType: T.Type) throws {
        try create(table: T.tableName, of: rootType)
    }

    func update(maps: [(PropertyConvertible, ColumnEncodable?)], tableName: String, condition: Condition? = nil) throws {
        var keys = [PropertyConvertible]()
        var values = [ColumnEncodable]()
        for (key, value) in maps {
            guard let val = value else {
                continue
            }
            keys.append(key)
            values.append(val)
        }
        try update(table: tableName, on: keys, with: values, where: condition)
    }

}

extension Database {

    func isColumnExist(tableName: String, columnName: String) throws -> Bool {
        return try getValue(on: Master.Properties.sql, fromTable: Master.builtinTableName, where: Master.Properties.tableName == tableName && Master.Properties.type == "table").stringValue.contains(columnName)
    }

}

fileprivate extension Database {

    func runTransaction(_ transaction: () throws -> Void) throws {
        do {
            try run(transaction: transaction)
        } catch {
            notifyError(error)
            throw error
        }
    }

    func tryGetValue(on result: ColumnResultConvertible, fromTable table: String, where condition: Condition? = nil, orderBy orderList: [OrderBy]? = nil, limit: Limit? = nil, offset: Offset? = nil) throws -> FundamentalValue {
        do {
            return try getValue(on: result, fromTable: table, where: condition, orderBy: orderList, limit: limit, offset: offset)
        } catch {
            notifyError(error)
            throw error
        }
    }

    func tryGetObjects<Object: TableDecodable>(on propertyConvertibleList: [PropertyConvertible], fromTable table: String, where condition: Condition? = nil, orderBy orderList: [OrderBy]? = nil, limit: Limit? = nil, offset: Offset? = nil) throws -> [Object] {
        do {
            return try getObjects(on: propertyConvertibleList, fromTable: table, where: condition, orderBy: orderList, limit: limit, offset: offset)
        } catch {
            notifyError(error)
            throw error
        }
    }

    func tryGetObject<Object: TableDecodable>(on propertyConvertibleList: [PropertyConvertible], fromTable table: String, where condition: Condition? = nil, orderBy orderList: [OrderBy]? = nil, offset: Offset? = nil) throws -> Object? {
        do {
            return try getObject(on: propertyConvertibleList, fromTable: table, where: condition, orderBy: orderList, offset: offset)
        } catch {
            notifyError(error)
            throw error
        }
    }

    func tryGetRows(on columnResultConvertibleList: [ColumnResultConvertible], fromTable table: String, where condition: Condition? = nil, orderBy orderList: [OrderBy]? = nil, limit: Limit? = nil, offset: Offset? = nil) throws -> FundamentalRowXColumn {
        do {
            return try getRows(on: columnResultConvertibleList, fromTable: table, where: condition, orderBy: orderList, limit: limit, offset: offset)
        } catch {
            notifyError(error)
            throw error
        }
    }

    func tryGetColumn(on result: ColumnResultConvertible, fromTable table: String, where condition: Condition? = nil, orderBy orderList: [OrderBy]? = nil, limit: Limit? = nil, offset: Offset? = nil) throws -> FundamentalColumn {
        do {
            return try getColumn(on: result, fromTable: table, where: condition, orderBy: orderList, limit: limit, offset: offset)
        } catch {
            notifyError(error)
            throw error
        }
    }

    func tryGetDistinctColumn(on result: ColumnResultConvertible, fromTable table: String, where condition: Condition? = nil, orderBy orderList: [OrderBy]? = nil, limit: Limit? = nil, offset: Offset? = nil) throws -> FundamentalColumn {
        do {
            return try getDistinctColumn(on: result, fromTable: table, where: condition, orderBy: orderList, limit: limit, offset: offset)
        } catch {
            notifyError(error)
            throw error
        }
    }

    func execQuery(on propertyConvertibleList: [PropertyConvertible], sql: String, values: [ColumnEncodable] = []) throws -> SelectSQL {
        do {
            return try prepareSelectSQL(on: propertyConvertibleList, sql: sql, values: values)
        } catch {
            notifyError(error)
            throw error
        }
    }

    private func notifyError(_ error: Swift.Error) {
        if let err = error as? WCDBSwift.Error {
            var userInfo = UIApplication.getTrackUserInfo()
            userInfo["sql"] = err.sql ?? ""
            userInfo["description"] = err.description
            userInfo["callStack"] = Thread.callStackSymbols.first ?? ""
            UIApplication.trackError("BaseDatabase", action: "track sql error", userInfo: userInfo)
        } else {
            UIApplication.traceError(error)
        }
    }
}
