import UIKit

class LiveMessageCell: PhotoRepresentableMessageCell {
    
    let badgeView = UIImageView(image: R.image.live_badge())
    let playButton = ModernNetworkOperationButton(type: .custom)
    
    override func render(viewModel: MessageViewModel) {
        super.render(viewModel: viewModel)
        if let viewModel = viewModel as? LiveMessageViewModel {
            badgeView.frame.origin = viewModel.badgeOrigin
            playButton.center = CGPoint(x: viewModel.contentFrame.midX, y: viewModel.contentFrame.midY)
            if let urlString = viewModel.message.thumbUrl, let url = URL(string: urlString) {
                contentImageView.sd_setImage(with: url)
            }
        }
    }
    
    override func prepare() {
        super.prepare()
        contentImageView.backgroundColor = .black
        contentView.addSubview(badgeView)
        playButton.style = .finished(showPlayIcon: true)
        playButton.sizeToFit()
        playButton.isUserInteractionEnabled = false
        contentView.addSubview(playButton)
        contentImageWrapperView.imageView.contentMode = .scaleAspectFill
    }
    
}
