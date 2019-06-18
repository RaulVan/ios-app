import UIKit

class AssetSnapshotCell: SnapshotCell {
    
    let assetIconView = AssetIconView(frame: CGRect(x: 0, y: 0, width: 42, height: 42))
    
    override func prepareForReuse() {
        super.prepareForReuse()
        assetIconView.prepareForReuse()
    }
    
    override func render(snapshot: SnapshotItem, asset: AssetItem? = nil) {
        super.render(snapshot: snapshot, asset: asset)
        if let asset = asset {
            assetIconView.setIcon(asset: asset)
        } else if let iconUrl = snapshot.assetIconUrl, let chainIconUrl = snapshot.assetChainIconUrl {
            assetIconView.setIcon(assetIconUrl: iconUrl, chainIconUrl: chainIconUrl)
        }
    }
    
    override func prepare() {
        super.prepare()
        infoView.iconWrapperView.addSubview(assetIconView)
        assetIconView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }
    
}
