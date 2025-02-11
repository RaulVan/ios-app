import Foundation

class DatabaseUserDefault {

    static let shared = DatabaseUserDefault()

    private var keyMixinDatabaseVersion: String {
        return "key_database_mixin_version_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyUpgradeStickers: String {
        return "key_upgrade_stickers_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyDatabaseVersion: String {
        return "key_database_version_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyForceUpgradeDatabase: String {
        return "key_force_upgrade_database_\(AccountAPI.shared.accountIdentityNumber)"
    }

    private let session = UserDefaults(suiteName: SuiteName.database)!
    let currentDatabaseVersion = 3

    var databaseVersion: Int {
        get {
            return session.integer(forKey: keyDatabaseVersion)
        }
        set {
            session.set(newValue, forKey: keyDatabaseVersion)
        }
    }

    func hasUpgradeDatabase() -> Bool {
        return forceUpgradeDatabase || databaseVersion != currentDatabaseVersion
    }

    var mixinDatabaseVersion: Int {
        return session.integer(forKey: keyMixinDatabaseVersion)
    }

    var upgradeStickers: Bool {
        get {
            return session.bool(forKey: keyUpgradeStickers)
        }
        set {
            session.set(newValue, forKey: keyUpgradeStickers)
        }
    }

    var forceUpgradeDatabase: Bool {
        get {
            return session.bool(forKey: keyForceUpgradeDatabase)
        }
        set {
            session.set(newValue, forKey: keyForceUpgradeDatabase)
        }
    }

}
