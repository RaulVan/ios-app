import UIKit

class AvatarSnapshotCell: SnapshotCell {
    
    let avatarImageView = AvatarImageView(frame: CGRect(x: 0, y: 0, width: 42, height: 42))
    
    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
        avatarImageView.titleLabel.text = nil
    }
    
    override func render(snapshot: SnapshotItem, asset: AssetItem? = nil) {
        super.render(snapshot: snapshot, asset: asset)
        if snapshot.type == SnapshotType.transfer.rawValue, let iconUrl = snapshot.opponentUserAvatarUrl, let userId = snapshot.opponentUserId, let name = snapshot.opponentUserFullName {
            avatarImageView.setImage(with: iconUrl, userId: userId, name: name)
        } else {
            avatarImageView.image = R.image.wallet.ic_transaction_external()
        }
    }
    
    override func prepare() {
        super.prepare()
        avatarImageView.cornerRadius = infoView.iconWrapperViewHeightConstraint.constant / 2
        infoView.iconWrapperView.addSubview(avatarImageView)
        avatarImageView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }
    
}
