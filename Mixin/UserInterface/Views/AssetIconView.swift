import UIKit

class AssetIconView: UIView {
    
    @IBInspectable var chainIconWidth: CGFloat = 10
    @IBInspectable var chainIconOutlineWidth: CGFloat = 2
    
    let iconImageView = UIImageView()
    let chainBackgroundView = WhiteBackgroundedView()
    let chainImageView = UIImageView()
    let shadowOffset: CGFloat = 5
    
    private var chainIconIsHidden = false {
        didSet {
            chainBackgroundView.isHidden = chainIconIsHidden
            chainImageView.isHidden = chainIconIsHidden
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        prepare()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        prepare()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        iconImageView.frame = bounds
        iconImageView.layer.cornerRadius = iconImageView.bounds.width / 2
        let chainBackgroundDiameter = chainIconWidth + chainIconOutlineWidth
        chainBackgroundView.frame = CGRect(x: 0,
                                           y: bounds.height - chainBackgroundDiameter,
                                           width: chainBackgroundDiameter,
                                           height: chainBackgroundDiameter)
        chainBackgroundView.layer.cornerRadius = chainBackgroundDiameter / 2
        chainImageView.bounds = CGRect(x: 0, y: 0, width: chainIconWidth, height: chainIconWidth)
        chainImageView.center = chainBackgroundView.center
        chainImageView.layer.cornerRadius = chainImageView.bounds.width / 2
        updateShadowPath(chainIconIsHidden: chainIconIsHidden)
    }
    
    func prepareForReuse() {
        iconImageView.sd_cancelCurrentImageLoad()
        chainImageView.sd_cancelCurrentImageLoad()
        iconImageView.image = nil
        chainImageView.image = nil
    }
    
    func setIcon(assetIconUrl: String, chainIconUrl: String?) {
        iconImageView.sd_setImage(with: URL(string: assetIconUrl), completed: nil)
        let shouldHideChainIcon: Bool
        if let str = chainIconUrl, let url = URL(string: str) {
            chainImageView.sd_setImage(with: url, completed: nil)
            shouldHideChainIcon = false
        } else {
            shouldHideChainIcon = true
        }
        if chainIconIsHidden != shouldHideChainIcon {
            updateShadowPath(chainIconIsHidden: shouldHideChainIcon)
        }
        chainIconIsHidden = shouldHideChainIcon
    }
    
    func setIcon(asset: AssetItem) {
        setIcon(assetIconUrl: asset.iconUrl, chainIconUrl: asset.chainIconUrl)
    }
    
    private func prepare() {
        backgroundColor = .clear
        iconImageView.clipsToBounds = true
        chainBackgroundView.clipsToBounds = true
        chainImageView.clipsToBounds = true
        addSubview(iconImageView)
        addSubview(chainBackgroundView)
        addSubview(chainImageView)
        updateShadowPath(chainIconIsHidden: false)
        layer.shadowColor = UIColor(rgbValue: 0x888888).cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 6
    }
    
    private func updateShadowPath(chainIconIsHidden: Bool) {
        let iconFrame = CGRect(x: 0,
                               y: iconImageView.frame.origin.y + shadowOffset,
                               width: iconImageView.frame.width,
                               height: iconImageView.frame.height)
        let shadowPath = UIBezierPath(ovalIn: iconFrame)
        if !chainIconIsHidden {
            let chainFrame = CGRect(x: 0,
                                    y: chainBackgroundView.frame.origin.y + shadowOffset,
                                    width: chainBackgroundView.frame.width,
                                    height: chainBackgroundView.frame.height)
            let chainPath = UIBezierPath(ovalIn: chainFrame)
            shadowPath.append(chainPath)
        }
        layer.shadowPath = shadowPath.cgPath
    }
    
}
