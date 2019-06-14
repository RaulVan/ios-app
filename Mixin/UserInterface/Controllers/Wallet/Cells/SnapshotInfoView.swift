import UIKit

class SnapshotInfoView: UIView {
    
    @IBOutlet weak var pendingDepositProgressView: UIView!
    @IBOutlet weak var iconWrapperView: UIView!
    @IBOutlet weak var iconButton: UIButton!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var amountLabel: InsetLabel!
    @IBOutlet weak var symbolLabel: UILabel!
    
    @IBOutlet weak var iconWrapperViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var pendingDepositProgressConstraint: NSLayoutConstraint!
    
    func render(snapshot: SnapshotItem, asset: AssetItem? = nil) {
        switch snapshot.type {
        case SnapshotType.deposit.rawValue:
            amountLabel.textColor = .walletGreen
            titleLabel.text = Localized.TRANSACTION_TYPE_DEPOSIT
        case SnapshotType.transfer.rawValue:
            if snapshot.amount.hasMinusPrefix {
                amountLabel.textColor = .walletRed
            } else {
                amountLabel.textColor = .walletGreen
            }
            titleLabel.text = Localized.TRANSACTION_TYPE_TRANSFER
        case SnapshotType.withdrawal.rawValue:
            amountLabel.textColor = .walletRed
            titleLabel.text = Localized.TRANSACTION_TYPE_WITHDRAWAL
        case SnapshotType.fee.rawValue:
            amountLabel.textColor = .walletRed
            titleLabel.text = Localized.TRANSACTION_TYPE_FEE
        case SnapshotType.rebate.rawValue:
            amountLabel.textColor = .walletGreen
            titleLabel.text = Localized.TRANSACTION_TYPE_REBATE
        case SnapshotType.pendingDeposit.rawValue:
            amountLabel.textColor = .walletGray
            if let finished = snapshot.confirmations, let total = asset?.confirmations {
                titleLabel.text = Localized.PENDING_DEPOSIT_CONFIRMATION(numerator: finished,
                                                                         denominator: total)
            } else {
                titleLabel.text = nil
            }
        default:
            break
        }
        amountLabel.text = CurrencyFormatter.localizedString(from: snapshot.amount, format: .precision, sign: .always)
        symbolLabel.text = asset?.symbol ?? snapshot.assetSymbol
        if snapshot.type == SnapshotType.pendingDeposit.rawValue, let finished = snapshot.confirmations, let total = asset?.confirmations {
            pendingDepositProgressView.isHidden = false
            let multiplier = CGFloat(finished) / CGFloat(total)
            if abs(pendingDepositProgressConstraint.multiplier - multiplier) > 0.1 {
                NSLayoutConstraint.deactivate([pendingDepositProgressConstraint])
                pendingDepositProgressConstraint = pendingDepositProgressView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: multiplier)
                NSLayoutConstraint.activate([pendingDepositProgressConstraint])
            }
        } else {
            pendingDepositProgressView.isHidden = true
        }
    }
    
}
