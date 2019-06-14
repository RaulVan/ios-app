import UIKit

class AllTransactionsViewController: TransactionsViewController<AvatarSnapshotCell> {
    
    class func instance() -> UIViewController {
        let vc = AllTransactionsViewController(category: .all)
        let container = ContainerViewController.instance(viewController: vc, title: Localized.WALLET_ALL_TRANSACTIONS_TITLE)
        container.automaticallyAdjustsScrollViewInsets = false
        return container
    }
    
}
