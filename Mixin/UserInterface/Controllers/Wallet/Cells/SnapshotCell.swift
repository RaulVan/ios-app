import UIKit

class SnapshotCell: UITableViewCell {
    
    let infoView: SnapshotInfoView = R.nib.snapshotInfoView(owner: nil)!
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        prepare()
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        prepare()
    }
    
    func render(snapshot: SnapshotItem, asset: AssetItem? = nil) {
        infoView.render(snapshot: snapshot, asset: asset)
    }
    
    func prepare() {
        selectedBackgroundView = UIView.createSelectedBackgroundView()
        infoView.amountLabel.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
        contentView.addSubview(infoView)
        infoView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }
    
}
