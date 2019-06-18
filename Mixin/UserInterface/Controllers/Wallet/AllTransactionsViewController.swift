import UIKit

class AllTransactionsViewController: TransactionsViewController<AvatarSnapshotCell> {
    
    class func instance() -> UIViewController {
        let vc = AllTransactionsViewController(category: .all)
        let container = ContainerViewController.instance(viewController: vc, title: Localized.WALLET_ALL_TRANSACTIONS_TITLE)
        container.automaticallyAdjustsScrollViewInsets = false
        return container
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        (cell as? AvatarSnapshotCell)?.delegate = self
        return cell
    }
    
}

extension AllTransactionsViewController: AvatarSnapshotCellDelegate {
    
    func avatarSnapshotCellDidSelectIcon(_ cell: AvatarSnapshotCell) {
        guard let indexPath = tableView.indexPath(for: cell) else {
            return
        }
        let snapshot = dataSource.snapshots[indexPath.section][indexPath.row]
        guard snapshot.type == SnapshotType.transfer.rawValue, let userId = snapshot.opponentUserId else {
            return
        }
        DispatchQueue.global().async {
            guard let user = UserDAO.shared.getUser(userId: userId), user.isCreatedByMessenger else {
                return
            }
            DispatchQueue.main.async {
                UserWindow.instance().updateUser(user: user).presentView()
            }
        }
    }
    
}
