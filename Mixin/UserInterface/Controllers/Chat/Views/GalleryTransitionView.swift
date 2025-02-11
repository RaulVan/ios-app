import UIKit
import YYImage

final class GalleryTransitionView: UIView, GalleryAnimatable {
    
    private let imageWrapperView = VerticalPositioningImageView()
    private let accessoryContainerView = UIView()
    private let shadowImageView = UIImageView(image: PhotoRepresentableMessageViewModel.shadowImage)
    private let timeLabel = UILabel()
    private let statusImageView = UIImageView()
    private let maskLayer = BubbleLayer()
    
    private var contentSize: CGSize?
    
    private var imageView: YYAnimatedImageView {
        return imageWrapperView.imageView
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        prepare()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        prepare()
    }
    
    func load(cell: PhotoRepresentableMessageCell) {
        guard let viewModel = cell.viewModel as? PhotoRepresentableMessageViewModel else {
            return
        }
        if let width = viewModel.message.mediaWidth, let height = viewModel.message.mediaHeight {
            contentSize = CGSize(width: width, height: height)
        } else {
            contentSize = nil
        }
        frame = cell.contentView.convert(cell.contentImageWrapperView.frame, to: superview)
        imageView.image = cell.contentImageView.image
        imageWrapperView.imageView.contentMode = cell.contentImageView.contentMode
        imageWrapperView.aspectRatio = cell.contentImageWrapperView.aspectRatio
        imageWrapperView.position = cell.contentImageWrapperView.position
        imageWrapperView.frame = bounds
        imageWrapperView.layoutIfNeeded()
        accessoryContainerView.transform = .identity
        accessoryContainerView.alpha = 1
        accessoryContainerView.frame = bounds
        shadowImageView.frame.origin = cell.contentView.convert(viewModel.shadowImageOrigin, to: cell.contentImageWrapperView)
        timeLabel.text = viewModel.time
        timeLabel.frame = cell.contentView.convert(viewModel.timeFrame, to: cell.contentImageWrapperView)
        statusImageView.image = viewModel.statusImage
        statusImageView.tintColor = viewModel.statusTintColor
        statusImageView.frame = cell.contentView.convert(viewModel.statusFrame, to: cell.contentImageWrapperView)
        let bubble = BubbleLayer.Bubble(style: viewModel.style)
        maskLayer.setBubble(bubble, frame: bounds, animationDuration: 0)
        maskLayer.bounds.size = imageWrapperView.bounds.size
        maskLayer.position = CGPoint(x: imageWrapperView.bounds.midX, y: imageWrapperView.bounds.midY)
    }
    
    func transition(to containerView: UIView) {
        let containerBounds = containerView.bounds
        let scale = containerBounds.width / bounds.width
        let frame: CGRect
        let bubbleFrame: CGRect
        
        let size: CGSize
        if let contentSize = contentSize {
            size = contentSize
        } else if let image = imageView.image {
            let imageRatio = image.size.width / image.size.height
            let imageWrapperRatio = imageWrapperView.frame.width / imageWrapperView.frame.height
            if imageRatio < imageWrapperRatio {
                size = image.size
            } else {
                size = imageWrapperView.frame.size
            }
        } else {
            size = imageWrapperView.frame.size
        }
        
        if GalleryItem.shouldLayoutImageOfRatioAsAriticle(size) {
            let height = min(containerBounds.height, containerBounds.width / size.width * size.height)
            let size = CGSize(width: containerBounds.width, height: height)
            let origin = CGPoint(x: 0, y: (containerBounds.height - height) / 2)
            frame = CGRect(origin: origin, size: size)
            bubbleFrame = CGRect(origin: .zero, size: size)
        } else {
            frame = size.rect(fittingSize: containerBounds.size)
            bubbleFrame = containerBounds
        }
        
        maskLayer.setBubble(.none, frame: bubbleFrame, animationDuration: animationDuration)
        animate(animations: {
            self.frame = frame
            self.imageWrapperView.frame = self.bounds
            self.accessoryContainerView.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            self.accessoryContainerView.transform = CGAffineTransform(scaleX: scale, y: scale)
            self.accessoryContainerView.alpha = 0
        }) 
    }
    
    func load(viewController: GalleryItemViewController) {
        guard let item = viewController.item, let superview = superview else {
            return
        }
        imageWrapperView.aspectRatio = item.size
        imageView.image = viewController.image
        if let controller = viewController as? GalleryImageItemViewController {
            var size = controller.imageView.bounds.size
            size.height = min(size.height, superview.bounds.height)
            bounds.size = size
            center = CGPoint(x: superview.bounds.midX, y: superview.bounds.midY)
            imageWrapperView.frame = bounds
            if item.shouldLayoutAsArticle, let relativeOffset = (viewController as? GalleryImageItemViewController)?.relativeOffset {
                imageWrapperView.position = .relativeOffset(relativeOffset)
            } else {
                imageWrapperView.position = .center
            }
            
            let scrollView = controller.scrollView
            var transform = CGAffineTransform.identity
            if scrollView.zoomScale != 1 {
                let scale = CGAffineTransform(scaleX: scrollView.zoomScale, y: scrollView.zoomScale)
                transform = transform.concatenating(scale)
            }
            if !item.shouldLayoutAsArticle {
                let x = scrollView.contentSize.width > scrollView.frame.width
                    ? scrollView.contentOffset.x + viewController.view.bounds.width / 2 - bounds.width * scrollView.zoomScale / 2
                    : 0
                let y = scrollView.contentSize.height > scrollView.frame.height
                    ? scrollView.contentOffset.y + viewController.view.bounds.height / 2 - bounds.height * scrollView.zoomScale / 2
                    : 0
                let offset = CGAffineTransform(translationX: -x, y: -y)
                transform = transform.concatenating(offset)
            }
            self.transform = transform
        } else if let controller = viewController as? GalleryVideoItemViewController {
            frame = controller.videoView.contentView.frame
            let wrapperWidth = bounds.height / item.size.height * item.size.width
            imageWrapperView.bounds.size = CGSize(width: wrapperWidth, height: bounds.height)
            imageWrapperView.center = CGPoint(x: bounds.midX, y: bounds.midY)
            imageWrapperView.position = .center
        } else {
            frame = viewController.view.bounds
            imageWrapperView.frame = bounds
            imageWrapperView.position = .center
        }
        imageWrapperView.layoutIfNeeded()
        maskLayer.setBubble(.none, frame: bounds, animationDuration: 0)
        maskLayer.frame = bounds
    }
    
    func transition(to cell: PhotoRepresentableMessageCell) {
        imageWrapperView.imageView.contentMode = cell.contentImageView.contentMode
        guard let viewModel = cell.viewModel as? PhotoRepresentableMessageViewModel else {
            return
        }
        let scale = bounds.width / cell.contentImageWrapperView.frame.width
        accessoryContainerView.transform = .identity
        accessoryContainerView.bounds.size = cell.contentImageWrapperView.bounds.size
        shadowImageView.frame.origin = cell.contentView.convert(viewModel.shadowImageOrigin, to: cell.contentImageWrapperView)
        timeLabel.text = viewModel.time
        timeLabel.frame = cell.contentView.convert(viewModel.timeFrame, to: cell.contentImageWrapperView)
        statusImageView.image = viewModel.statusImage
        statusImageView.tintColor = viewModel.statusTintColor
        statusImageView.frame = cell.contentView.convert(viewModel.statusFrame, to: cell.contentImageWrapperView)
        
        accessoryContainerView.transform = CGAffineTransform(scaleX: scale, y: scale)
        accessoryContainerView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        accessoryContainerView.alpha = 0
        
        let frame = cell.contentView.convert(cell.contentImageWrapperView.frame, to: superview)
        let bounds = CGRect(origin: .zero, size: frame.size)

        let bubble = BubbleLayer.Bubble(style: viewModel.style)
        maskLayer.setBubble(bubble, frame: bounds, animationDuration: animationDuration)
        
        animate(animations: {
            self.transform = .identity
            self.frame = frame
            self.imageWrapperView.frame = bounds
            self.accessoryContainerView.transform = .identity
            self.accessoryContainerView.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            self.accessoryContainerView.alpha = 1
        }, completion: {
        })
    }
    
    private func prepare() {
        accessoryContainerView.backgroundColor = .clear
        timeLabel.backgroundColor = .clear
        timeLabel.font = DetailInfoMessageViewModel.timeFont
        timeLabel.textAlignment = .right
        timeLabel.textColor = .white
        statusImageView.contentMode = .left
        shadowImageView.frame.size = shadowImageView.image?.size ?? .zero
        imageWrapperView.backgroundColor = .black
        addSubview(imageWrapperView)
        accessoryContainerView.addSubview(shadowImageView)
        accessoryContainerView.addSubview(timeLabel)
        accessoryContainerView.addSubview(statusImageView)
        addSubview(accessoryContainerView)
        layer.mask = maskLayer
    }
    
}
