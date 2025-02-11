import Foundation
import WCDBSwift

class IdentityDAO: SignalDAO {

    static let shared = IdentityDAO()

    func getLocalIdentity() -> Identity? {
        return SignalDatabase.shared.getCodable(condition: Identity.Properties.address == "-1")
    }

    func getCount() -> Int {
        return SignalDatabase.shared.getCount(on: Identity.Properties.id.count(), fromTable: Identity.tableName)
    }

    func saveLocalIdentity() {
        let registrationId = UserDefaults.standard.value(forKey: PreKeyUtil.localRegistrationId) as! Int
        let publicKey = UserDefaults.standard.value(forKey: PreKeyUtil.localPublicKey) as! Data
        let privateKey = UserDefaults.standard.value(forKey: PreKeyUtil.localPrivateKey) as! Data
        IdentityDAO.shared.insertOrReplace(obj: Identity(address: "-1", registrationId: registrationId, publicKey: publicKey, privateKey: privateKey, nextPreKeyId: nil, timestamp: Date().timeIntervalSince1970))
    }
}
