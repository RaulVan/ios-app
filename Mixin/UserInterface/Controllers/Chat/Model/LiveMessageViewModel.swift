import UIKit

class LiveMessageViewModel: PhotoRepresentableMessageViewModel {
    
    private let badgeMargin = Margin(leading: 12, trailing: 4, top: 3, bottom: 0)
    
    override class var bubbleImageProvider: BubbleImageProvider.Type {
        return LightRightBubbleImageProvider.self
    }
    
    var badgeOrigin = CGPoint.zero
    
    override func didSetStyle() {
        super.didSetStyle()
        if style.contains(.received) {
            badgeOrigin = CGPoint(x: contentFrame.origin.x + badgeMargin.leading,
                                  y: contentFrame.origin.y + badgeMargin.top)
        } else {
            badgeOrigin = CGPoint(x: contentFrame.origin.x + badgeMargin.trailing,
                                  y: contentFrame.origin.y + badgeMargin.top)
        }
    }
    
}
