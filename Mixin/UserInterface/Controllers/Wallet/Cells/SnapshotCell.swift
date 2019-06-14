import UIKit

protocol SnapshotCellDelegate: class {
    func walletSnapshotCellDidSelectIcon(_ cell: SnapshotCell)
}

class SnapshotCell: UITableViewCell {
    
    let infoView: SnapshotInfoView = R.nib.snapshotInfoView(owner: nil)!
    
    weak var delegate: SnapshotCellDelegate?
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        prepare()
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        prepare()
    }
    
    @objc func selectIconAction() {
        delegate?.walletSnapshotCellDidSelectIcon(self)
    }
    
    func render(snapshot: SnapshotItem, asset: AssetItem? = nil) {
        infoView.render(snapshot: snapshot, asset: asset)
    }
    
    func prepare() {
        selectedBackgroundView = UIView.createSelectedBackgroundView()
        infoView.amountLabel.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
        infoView.iconButton.addTarget(self, action: #selector(selectIconAction), for: .touchUpInside)
        contentView.addSubview(infoView)
        infoView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }
    
}
