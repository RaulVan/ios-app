import UIKit

class DataMessageViewModel: CardMessageViewModel, AttachmentLoadingViewModel {

    var isLoading = false
    var progress: Double?
    var showPlayIconOnMediaStatusDone: Bool = false
    var operationButtonStyle: NetworkOperationButton.Style = .finished(showPlayIcon: false)
    var downloadIsTriggeredByUser = false
    
    override var size: CGSize {
        return CGSize(width: 280, height: 72)
    }
    
    var shouldAutoDownload: Bool {
        switch CommonUserDefault.shared.autoDownloadFiles {
        case .never:
            return false
        case .wifi:
            return NetworkManager.shared.isReachableOnWiFi
        case .wifiAndCellular:
            return true
        }
    }
    
    var automaticallyLoadsAttachment: Bool {
        return !shouldUpload && shouldAutoDownload
    }
    
    override init(message: MessageItem, style: Style, fits layoutWidth: CGFloat) {
        super.init(message: message, style: style, fits: layoutWidth)
        updateOperationButtonStyle()
    }
    
    func beginAttachmentLoading(isTriggeredByUser: Bool) {
        downloadIsTriggeredByUser = isTriggeredByUser
        defer {
            updateOperationButtonStyle()
        }
        guard shouldBeginAttachmentLoading(isTriggeredByUser: isTriggeredByUser) else {
            return
        }
        MessageDAO.shared.updateMediaStatus(messageId: message.messageId, status: .PENDING, conversationId: message.conversationId)
        if shouldUpload {
            UploaderQueue.shared.addJob(job: FileUploadJob(message: Message.createMessage(message: message)))
        } else {
            ConcurrentJobQueue.shared.addJob(job: FileDownloadJob(messageId: message.messageId, mediaMimeType: message.mediaMimeType))
        }
        isLoading = true
    }
    
    func cancelAttachmentLoading(isTriggeredByUser: Bool) {
        guard isTriggeredByUser || !downloadIsTriggeredByUser else {
            return
        }
        if shouldUpload {
            UploaderQueue.shared.cancelJob(jobId: FileUploadJob.jobId(messageId: message.messageId))
        } else {
            ConcurrentJobQueue.shared.cancelJob(jobId: FileDownloadJob.jobId(messageId: message.messageId))
        }
        if isTriggeredByUser {
            MessageDAO.shared.updateMediaStatus(messageId: message.messageId, status: .CANCELED, conversationId: message.conversationId)
        }
    }
    
}
