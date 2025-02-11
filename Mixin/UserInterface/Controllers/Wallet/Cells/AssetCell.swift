import UIKit

class AssetCell: UITableViewCell {
    
    static let height: CGFloat = 74
    static let balanceAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont(name: "DINCondensed-Bold", size: 19)!,
        .foregroundColor: UIColor.darkText,
        .kern: 0.7
    ]
    static let symbolAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: UIColor.darkText
    ]
    
    @IBOutlet weak var assetIconView: AssetIconView!
    @IBOutlet weak var balanceLabel: InsetLabel!
    @IBOutlet weak var symbolLabel: InsetLabel!
    @IBOutlet weak var changeLabel: InsetLabel!
    @IBOutlet weak var fiatMoneyPriceLabel: UILabel!
    @IBOutlet weak var fiatMoneyBalanceLabel: UILabel!
    @IBOutlet weak var noFiatMoneyPriceIndicatorLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        balanceLabel.contentInset = UIEdgeInsets(top: 1, left: 0, bottom: 0, right: 0)
        symbolLabel.contentInset = UIEdgeInsets(top: 1, left: 0, bottom: 3, right: 0)
        changeLabel.contentInset = UIEdgeInsets(top: 1, left: 0, bottom: 4, right: 0)
        selectedBackgroundView = UIView(frame: bounds)
        selectedBackgroundView!.backgroundColor = .modernCellSelection
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        assetIconView.prepareForReuse()
    }
    
    func render(asset: AssetItem, attributedSymbol: NSAttributedString? = nil) {
        assetIconView.setIcon(asset: asset)
        let balance: String
        if asset.balance == "0" {
            balance = "0\(currentDecimalSeparator)00"
        } else {
            balance = CurrencyFormatter.localizedString(from: asset.balance, format: .pretty, sign: .never) ?? ""
        }
        balanceLabel.attributedText = NSAttributedString(string: balance, attributes: AssetCell.balanceAttributes)
        if let attributedSymbol = attributedSymbol {
            symbolLabel.attributedText = attributedSymbol
        } else {
            symbolLabel.attributedText = NSAttributedString(string: asset.symbol, attributes: AssetCell.symbolAttributes)
        }
        if asset.priceUsd.doubleValue > 0 {
            changeLabel.text = " \(asset.localizedUsdChange)%"
            if asset.changeUsd.doubleValue > 0 {
                changeLabel.textColor = .walletGreen
            } else {
                changeLabel.textColor = .walletRed
            }
            fiatMoneyPriceLabel.text = Currency.current.symbol + asset.localizedFiatMoneyPrice
            changeLabel.alpha = 1
            fiatMoneyPriceLabel.alpha = 1
            noFiatMoneyPriceIndicatorLabel.alpha = 0
        } else {
            changeLabel.text = Localized.WALLET_NO_PRICE // Just for layout guidance
            fiatMoneyPriceLabel.text = nil
            changeLabel.alpha = 0
            fiatMoneyPriceLabel.alpha = 0
            noFiatMoneyPriceIndicatorLabel.alpha = 1
        }
        fiatMoneyBalanceLabel.text = asset.localizedFiatMoneyBalance
    }

}
