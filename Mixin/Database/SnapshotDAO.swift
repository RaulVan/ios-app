import WCDBSwift

final class SnapshotDAO {
    
    static let shared = SnapshotDAO()
    
    private let createdAt = Snapshot.Properties.createdAt.in(table: Snapshot.tableName)
    
    private let selectSql = """
SELECT snapshots.*, assets.symbol, assets.icon_url, chain.icon_url as chain_icon_url, users.user_id, users.full_name, users.avatar_url, users.identity_number
FROM snapshots
LEFT JOIN assets ON snapshots.asset_id = assets.asset_id
LEFT JOIN users ON snapshots.opponent_id = users.user_id
LEFT JOIN assets AS chain ON assets.chain_id = chain.asset_id
"""
    
    func getSnapshots(assetId: String? = nil, below location: SnapshotItem? = nil, sort: Snapshot.Sort, filter: Snapshot.Filter, limit: Int) -> [SnapshotItem] {
        var sql = selectSql
        
        var conditions: [String] = []
        var args: [ColumnEncodable] = []
        
        if let assetId = assetId {
            conditions.append("snapshots.asset_id = ?")
            args.append(assetId)
        }
        
        let sortAndFilter = self.conditions(sort: sort, filter: filter, location: location)
        conditions.append(contentsOf: sortAndFilter.conditions)
        args.append(contentsOf: sortAndFilter.args)
        
        if !conditions.isEmpty {
            let condition = conditions.joined(separator: " AND ")
            sql += " WHERE " + condition
        }
        
        sql += orderBySql(sort: sort)
        sql += limitSql(limit: limit)
        
        print(sql)
        return getSnapshotsAndRefreshCorrespondingAssetIfNeeded(sql: sql, values: args)
    }
    
    func getSnapshots(opponentId: String, below location: SnapshotItem? = nil, sort: Snapshot.Sort, filter: Snapshot.Filter, limit: Int) -> [SnapshotItem] {
        var sql = selectSql
        
        var conditions: [String] = ["snapshots.opponent_id = ?"]
        var args: [ColumnEncodable] = [opponentId]
        
        let sortAndFilter = self.conditions(sort: sort, filter: filter, location: location)
        conditions.append(contentsOf: sortAndFilter.conditions)
        args.append(contentsOf: sortAndFilter.args)
        
        let condition = conditions.joined(separator: " AND ")
        sql += " WHERE " + condition
        
        sql += orderBySql(sort: sort)
        sql += limitSql(limit: limit)
        
        print(sql)
        return getSnapshotsAndRefreshCorrespondingAssetIfNeeded(sql: sql, values: args)
    }
    
    func getSnapshot(snapshotId: String) -> SnapshotItem? {
        let sql = selectSql
            + " WHERE snapshots.snapshot_id = ?"
            + " ORDER BY snapshots.created_at DESC"
            + limitSql(limit: 1)
        print(sql)
        return getSnapshotsAndRefreshCorrespondingAssetIfNeeded(sql: sql, values: [snapshotId]).first
    }
    
    func insertOrReplaceSnapshots(snapshots: [Snapshot], userInfo: [AnyHashable: Any]? = nil) {
        MixinDatabase.shared.insertOrReplace(objects: snapshots)
        NotificationCenter.default.afterPostOnMain(name: .SnapshotDidChange, object: nil, userInfo: userInfo)
    }
    
    func replacePendingDeposits(assetId: String, pendingDeposits: [PendingDeposit]) {
        let snapshots = pendingDeposits.map({ $0.makeSnapshot(assetId: assetId )})
        MixinDatabase.shared.transaction { (db) in
            try db.delete(fromTable: Snapshot.tableName,
                          where: Snapshot.Properties.assetId == assetId && Snapshot.Properties.type == SnapshotType.pendingDeposit.rawValue)
            if snapshots.count > 0 {
                try db.insertOrReplace(objects: snapshots, intoTable: Snapshot.tableName)
            }
        }
    }
    
    func removePendingDeposits(assetId: String, transactionHash: String) {
        let condition = Snapshot.Properties.assetId == assetId
            && Snapshot.Properties.transactionHash == transactionHash
            && Snapshot.Properties.type == SnapshotType.pendingDeposit.rawValue
        MixinDatabase.shared.delete(table: Snapshot.tableName, condition: condition)
    }
    
}

extension SnapshotDAO {
    
    private func getSnapshotsAndRefreshCorrespondingAssetIfNeeded(sql: String, values: [ColumnEncodable]) -> [SnapshotItem] {
        let snapshots: [SnapshotItem] = MixinDatabase.shared.getCodables(sql: sql, values: values)
        for snapshot in snapshots where snapshot.assetSymbol == nil {
            let job = RefreshAssetsJob(assetId: snapshot.assetId)
            ConcurrentJobQueue.shared.addJob(job: job)
        }
        return snapshots
    }
    
    private func refreshAssetIfNeeded(_ snapshot: SnapshotItem) {
        guard snapshot.assetSymbol == nil else {
            return
        }
        let job = RefreshAssetsJob(assetId: snapshot.assetId)
        ConcurrentJobQueue.shared.addJob(job: job)
    }
    
    private func conditions(sort: Snapshot.Sort, filter: Snapshot.Filter, location: SnapshotItem?) -> (conditions: [String], args: [ColumnEncodable]) {
        var conditions: [String] = []
        var args: [ColumnEncodable] = []
        
        if let location = location {
            switch sort {
            case .createdAt:
                conditions.append("snapshots.created_at < ?")
                args.append(location.createdAt)
            case .amount:
                conditions.append("(ABS(snapshots.amount) < ABS(?) OR (ABS(snapshots.amount) = ABS(?) AND snapshots.created_at < ?))")
                args.append(contentsOf: [location.amount, location.amount, location.createdAt])
            }
        }
        
        if filter != .all {
            let types = filter.snapshotTypes.map({ $0.rawValue })
            let wildcards = [String](repeating: "?", count: types.count).joined(separator: ",")
            conditions.append("snapshots.type IN (\(wildcards))")
            args.append(contentsOf: types)
        }
        
        return (conditions, args)
    }
    
    private func orderBySql(sort: Snapshot.Sort) -> String {
        switch sort {
        case .createdAt:
            return " ORDER BY snapshots.created_at DESC"
        case .amount:
            return " ORDER BY ABS(snapshots.amount) DESC, snapshots.created_at DESC"
        }
    }
    
    private func limitSql(limit: Int) -> String {
        return " LIMIT \(limit)"
    }
    
}
