import UIKit

class TransactionViewController: UIViewController {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var headerContentStackView: UIStackView!
    @IBOutlet weak var assetIconView: AssetIconView!
    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var symbolLabel: InsetLabel!
    @IBOutlet weak var fiatMoneyValueLabel: UILabel!
    
    @IBOutlet weak var avatarImageViewWidthConstraint: ScreenSizeCompatibleLayoutConstraint!
    
    private let cellReuseId = "cell"
    
    private var asset: AssetItem!
    private var snapshot: SnapshotItem!
    private var contents: [(title: String, subtitle: String?)]!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if ScreenSize.current >= .inch6_1 {
            assetIconView.chainIconWidth = 28
            assetIconView.chainIconOutlineWidth = 4
            tableView.tableHeaderView?.frame.size.height = 210
            headerContentStackView.spacing = 5
        }
        view.layoutIfNeeded()
        symbolLabel.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
        assetIconView.setIcon(asset: asset)
        amountLabel.text = CurrencyFormatter.localizedString(from: snapshot.amount, format: .precision, sign: .always)
        if snapshot.amount.hasMinusPrefix {
            amountLabel.textColor = .walletRed
        } else {
            amountLabel.textColor = .walletGreen
        }
        let fiatMoneyValue = snapshot.amount.doubleValue * asset.priceUsd.doubleValue * Currency.current.rate
        if let value = CurrencyFormatter.localizedString(from: fiatMoneyValue, format: .fiatMoney, sign: .never) {
            fiatMoneyValueLabel.text = "≈ " + Currency.current.symbol + value
        } else {
            fiatMoneyValueLabel.text = nil
        }
        symbolLabel.text = snapshot.assetSymbol
        makeContents()
        tableView.dataSource = self
        tableView.delegate = self
        updateTableViewContentInsetBottom()
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateTableViewContentInsetBottom()
    }
    
    class func instance(asset: AssetItem, snapshot: SnapshotItem) -> UIViewController {
        let vc = Storyboard.wallet.instantiateViewController(withIdentifier: "transaction") as! TransactionViewController
        vc.asset = asset
        vc.snapshot = snapshot
        let container = ContainerViewController.instance(viewController: vc, title: Localized.TRANSACTION_TITLE)
        return container
    }
    
}

extension TransactionViewController: ContainerViewControllerDelegate {
    
    var prefersNavigationBarSeparatorLineHidden: Bool {
        return true
    }
    
}

extension TransactionViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contents.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId) as! TransactionCell
        cell.titleLabel.text = contents[indexPath.row].title
        cell.subtitleLabel.text = contents[indexPath.row].subtitle
        return cell
    }
    
}

extension TransactionViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard snapshot.type == SnapshotType.transfer.rawValue else {
            return
        }
        var transferUserId: String?
        if indexPath.row == 3 && snapshot.amount.doubleValue > 0 {
            transferUserId = snapshot.opponentId
        } else if indexPath.row == 4 && snapshot.amount.doubleValue < 0 {
            transferUserId = snapshot.opponentId
        }
        guard let userId = transferUserId, !userId.isEmpty else {
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
    
    func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        return canCopyAction(indexPath: indexPath).0
    }
    
    func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        return canCopyAction(indexPath: indexPath).0 && action == #selector(copy(_:))
    }
    
    func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        let copy: (can: Bool, body: String) = canCopyAction(indexPath: indexPath)
        guard copy.can else {
            return
        }
        UIPasteboard.general.string = copy.body
        showAutoHiddenHud(style: .notification, text: Localized.TOAST_COPIED)
    }
    
}

extension TransactionViewController {
    
    private func updateTableViewContentInsetBottom() {
        if view.safeAreaInsets.bottom > 20 {
            tableView.contentInset.bottom = 0
        } else {
            tableView.contentInset.bottom = 20
        }
    }
    
    private func makeContents() {
        contents = []
        // 0
        contents.append((title: Localized.TRANSACTION_ID, subtitle: snapshot.snapshotId))
        // 1
        switch snapshot.type {
        case SnapshotType.deposit.rawValue:
            contents.append((title: Localized.TRANSACTION_TYPE, subtitle: Localized.TRANSACTION_TYPE_DEPOSIT))
        case SnapshotType.transfer.rawValue:
            contents.append((title: Localized.TRANSACTION_TYPE, subtitle: Localized.TRANSACTION_TYPE_TRANSFER))
        case SnapshotType.withdrawal.rawValue:
            contents.append((title: Localized.TRANSACTION_TYPE, subtitle: Localized.TRANSACTION_TYPE_WITHDRAWAL))
        case SnapshotType.fee.rawValue:
            contents.append((title: Localized.TRANSACTION_TYPE, subtitle: Localized.TRANSACTION_TYPE_FEE))
        case SnapshotType.rebate.rawValue:
            contents.append((title: Localized.TRANSACTION_TYPE, subtitle: Localized.TRANSACTION_TYPE_REBATE))
        default:
            break
        }
        // 2
        contents.append((title: Localized.TRANSACTION_ASSET, subtitle: asset.name))
        // 3
        switch snapshot.type {
        case SnapshotType.deposit.rawValue:
            if asset.isAccount {
                contents.append((title: Localized.WALLET_ACCOUNT_NAME, subtitle: snapshot.sender))
            } else {
                contents.append((title: Localized.TRANSACTION_SENDER, subtitle: snapshot.sender))
            }
        case SnapshotType.transfer.rawValue:
            if snapshot.amount.doubleValue > 0 {
                contents.append((title: Localized.WALLET_SNAPSHOT_FROM(fullName: ""), subtitle: snapshot.opponentUserFullName))
            } else {
                contents.append((title: Localized.WALLET_SNAPSHOT_FROM(fullName: ""), subtitle: AccountAPI.shared.account?.full_name))
            }
        case SnapshotType.withdrawal.rawValue, SnapshotType.fee.rawValue, SnapshotType.rebate.rawValue:
            contents.append((title: Localized.TRANSACTION_TRANSACTION_HASH, subtitle: snapshot.transactionHash))
        default:
            break
        }
        // 4
        switch snapshot.type {
        case SnapshotType.deposit.rawValue:
            contents.append((title: Localized.TRANSACTION_TRANSACTION_HASH, subtitle: snapshot.transactionHash))
        case SnapshotType.transfer.rawValue:
            if snapshot.amount.doubleValue > 0 {
                contents.append((title: Localized.WALLET_SNAPSHOT_TO(fullName: ""), subtitle: AccountAPI.shared.account?.full_name))
            } else {
                contents.append((title: Localized.WALLET_SNAPSHOT_TO(fullName: ""), subtitle: snapshot.opponentUserFullName))
            }
        case SnapshotType.withdrawal.rawValue, SnapshotType.fee.rawValue, SnapshotType.rebate.rawValue:
            if asset.isAccount {
                contents.append((title: Localized.WALLET_ACCOUNT_NAME, subtitle: snapshot.receiver))
            } else {
                contents.append((title: Localized.TRANSACTION_RECEIVER, subtitle: snapshot.receiver))
            }
        default:
            break
        }
        // 5
        if asset.isAccount && (snapshot.type == SnapshotType.deposit.rawValue || snapshot.type == SnapshotType.withdrawal.rawValue || snapshot.type == SnapshotType.fee.rawValue || snapshot.type == SnapshotType.rebate.rawValue) {
            contents.append((title: Localized.WALLET_ACCOUNT_MEMO, subtitle: snapshot.memo))
        } else {
            contents.append((title: Localized.TRANSACTION_MEMO, subtitle: snapshot.memo))
        }
        // 6
        contents.append((title: Localized.TRANSACTION_DATE, subtitle: DateFormatter.dateFull.string(from: snapshot.createdAt.toUTCDate())))
    }
    
    private func canCopyAction(indexPath: IndexPath) -> (Bool, String) {
        switch indexPath.row {
        case 0:
            return (true, snapshot.snapshotId)
        case 3:
            switch snapshot.type {
            case SnapshotType.deposit.rawValue:
                return (true, snapshot.sender ?? "")
            case SnapshotType.withdrawal.rawValue, SnapshotType.fee.rawValue, SnapshotType.rebate.rawValue:
                return (true, snapshot.transactionHash ?? "")
            default:
                break
            }
        case 4:
            switch snapshot.type {
            case SnapshotType.deposit.rawValue:
                return (true, snapshot.transactionHash ?? "")
            case SnapshotType.withdrawal.rawValue, SnapshotType.fee.rawValue, SnapshotType.rebate.rawValue:
                return (true, snapshot.receiver ?? "")
            default:
                break
            }
        default:
            break
        }
        return (false, "")
    }
    
}
