import Foundation
import WCDBSwift

class AssetItem: TableCodable, NumberStringLocalizable, AssetKeyConvertible {
    
    let assetId: String
    let type: String
    let symbol: String
    let name: String
    let iconUrl: String
    let balance: String
    let publicKey: String?
    let priceBtc: String
    let priceUsd: String
    let chainId: String
    let chainIconUrl: String?
    let changeUsd: String
    let confirmations: Int
    var accountName: String?
    var accountTag: String?
    let assetKey: String
    let chainName: String?
    
    enum CodingKeys: String, CodingTableKey {
        static let objectRelationalMapping = TableBinding(CodingKeys.self)
        
        typealias Root = AssetItem
        case assetId = "asset_id"
        case type
        case symbol
        case name
        case iconUrl = "icon_url"
        case balance
        case publicKey = "public_key"
        case priceBtc = "price_btc"
        case priceUsd = "price_usd"
        case changeUsd = "change_usd"
        case chainId = "chain_id"
        case chainIconUrl = "chain_icon_url"
        case confirmations
        case accountName = "account_name"
        case accountTag = "account_tag"
        case assetKey = "asset_key"
        case chainName = "chain_name"
    }
    
    lazy var localizedBalance = localizedNumberString(balance)
    
    lazy var localizedFiatMoneyPrice: String = {
        let value = priceUsd.doubleValue * Currency.current.rate
        return CurrencyFormatter.localizedString(from: value, format: .fiatMoneyPrice, sign: .never) ?? ""
    }()
    
    lazy var localizedFiatMoneyBalance: String = {
        let fiatMoneyBalance = balance.doubleValue * priceUsd.doubleValue * Currency.current.rate
        if let value = CurrencyFormatter.localizedString(from: fiatMoneyBalance, format: .fiatMoney, sign: .never) {
            return "≈ " + Currency.current.symbol + value
        } else {
            return ""
        }
    }()
    
    lazy var localizedUsdChange: String = {
        let usdChange = changeUsd.doubleValue * 100
        return CurrencyFormatter.localizedString(from: usdChange, format: .fiatMoney, sign: .whenNegative) ?? "0\(currentDecimalSeparator)00"
    }()
    
    lazy var depositTips: String = {
        switch chainId {
        case "c6d0c728-2624-429b-8e0d-d9d19b6592fa":
            return R.string.localizable.wallet_deposit_btc() + Localized.WALLET_DEPOSIT_CONFIRMATIONS(confirmations: confirmations)
        case "6cfe566e-4aad-470b-8c9a-2fd35b49c68d":
            return R.string.localizable.wallet_deposit_eos() + Localized.WALLET_DEPOSIT_CONFIRMATIONS(confirmations: confirmations)
        case "43d61dcd-e413-450d-80b8-101d5e903357":
            return R.string.localizable.wallet_deposit_eth() + Localized.WALLET_DEPOSIT_CONFIRMATIONS(confirmations: confirmations)
        case "25dabac5-056a-48ff-b9f9-f67395dc407c":
            return R.string.localizable.wallet_deposit_trx() + Localized.WALLET_DEPOSIT_CONFIRMATIONS(confirmations: confirmations)
        default:
            return R.string.localizable.wallet_deposit_other(symbol) + Localized.WALLET_DEPOSIT_CONFIRMATIONS(confirmations: confirmations)
        }
    }()
    
    init(assetId: String, type: String, symbol: String, name: String, iconUrl: String, balance: String, publicKey: String?, priceBtc: String, priceUsd: String, chainId: String, chainIconUrl: String?, changeUsd: String, confirmations: Int, accountName: String?, accountTag: String?, assetKey: String, chainName: String?) {
        self.assetId = assetId
        self.type = type
        self.symbol = symbol
        self.name = name
        self.iconUrl = iconUrl
        self.balance = balance
        self.publicKey = publicKey
        self.priceBtc = priceBtc
        self.priceUsd = priceUsd
        self.chainId = chainId
        self.chainIconUrl = chainIconUrl
        self.changeUsd = changeUsd
        self.confirmations = confirmations
        self.accountName = accountName
        self.accountTag = accountTag
        self.assetKey = assetKey
        self.chainName = chainName
    }
    
}

extension AssetItem {
    
    static func createAsset(asset: Asset, chainIconUrl: String?, chainName: String?) -> AssetItem {
        return AssetItem(assetId: asset.assetId, type: asset.type, symbol: asset.symbol, name: asset.name, iconUrl: asset.iconUrl, balance: asset.balance, publicKey: asset.publicKey, priceBtc: asset.priceBtc, priceUsd: asset.priceUsd, chainId: asset.chainId, chainIconUrl: chainIconUrl, changeUsd: asset.changeUsd, confirmations: asset.confirmations, accountName: asset.accountName, accountTag: asset.accountTag, assetKey: asset.assetKey, chainName: chainName)
    }
    
    static func createDefaultAsset() -> AssetItem  {
        return AssetItem(assetId: "c94ac88f-4671-3976-b60a-09064f1811e8", type: "", symbol: "XIN", name: "Mixin", iconUrl: "https://images.mixin.one/UasWtBZO0TZyLTLCFQjvE_UYekjC7eHCuT_9_52ZpzmCC-X-NPioVegng7Hfx0XmIUavZgz5UL-HIgPCBECc-Ws=s128", balance: "0", publicKey: nil, priceBtc: "0", priceUsd: "0", chainId: "43d61dcd-e413-450d-80b8-101d5e903357", chainIconUrl: "https://images.mixin.one/zVDjOxNTQvVsA8h2B4ZVxuHoCF3DJszufYKWpd9duXUSbSapoZadC7_13cnWBqg0EmwmRcKGbJaUpA8wFfpgZA=s128", changeUsd: "0", confirmations: 100, accountName: nil, accountTag: nil, assetKey: "0xa974c709cfb4566686553a20790685a47aceaa33", chainName: "Ether")
    }
    
}
