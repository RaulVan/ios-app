import UIKit

class PeerTransactionsViewController: TransactionsViewController<AssetSnapshotCell> {
    
    class func instance(opponentId: String) -> UIViewController {
        let vc = PeerTransactionsViewController(category: .user(id: opponentId))
        let container = ContainerViewController.instance(viewController: vc, title: Localized.PROFILE_TRANSACTIONS)
        container.automaticallyAdjustsScrollViewInsets = false
        return container
    }
    
}
