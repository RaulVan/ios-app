import Foundation
import Photos

class VideoUploadJob: AttachmentUploadJob {
    
    private lazy var videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 1280,
        AVVideoHeightKey: 720,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 1500000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel
        ]
    ]
    private lazy var audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey: 2,
        AVSampleRateKey: 44100,
        AVEncoderBitRateKey: 128000
    ]
    
    override var fileUrl: URL? {
        guard let mediaUrl = message.mediaUrl else {
            return nil
        }
        return MixinFile.url(ofChatDirectory: .videos, filename: mediaUrl)
    }
    
    override class func jobId(messageId: String) -> String {
        return "video-upload-\(messageId)"
    }
    
    override func execute() -> Bool {
        guard !isCancelled, AccountAPI.shared.didLogin else {
            return false
        }
        if message.mediaUrl != nil {
            return super.execute()
        } else if let localIdentifier = message.mediaLocalIdentifier {
            updateMessageMediaUrl(with: localIdentifier)
            if message.mediaUrl != nil {
                return super.execute()
            } else {
                return false
            }
        } else {
            return false
        }
    }
    
    private func updateMessageMediaUrl(with mediaLocalIdentifier: String) {
        guard let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [mediaLocalIdentifier], options: nil).firstObject else {
            MessageDAO.shared.updateMediaStatus(messageId: message.messageId, status: .EXPIRED, conversationId: message.conversationId)
            return
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        
        var avAsset: AVAsset?
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { (asset, audioMix, info) in
            avAsset = asset
            semaphore.signal()
        }
        semaphore.wait()
        
        guard !isCancelled, let asset = avAsset else {
            return
        }
        let filename = message.messageId
        let videoFilename = filename + ExtensionName.mp4.withDot
        let videoUrl = MixinFile.url(ofChatDirectory: .videos, filename: videoFilename)
        let exportSession = AssetExportSession(asset: asset, videoSettings: videoSettings, audioSettings: audioSettings, outputURL: videoUrl)
        exportSession.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()
        
        guard !isCancelled, exportSession.status == .completed else {
            try? FileManager.default.removeItem(at: videoUrl)
            return
        }
        let thumbnail = UIImage(withFirstFrameOfVideoAtAsset: asset)
        let thumbnailFilename = filename + ExtensionName.jpeg.withDot
        let thumbnailUrl = MixinFile.url(ofChatDirectory: .videos, filename: thumbnailFilename)
        thumbnail?.saveToFile(path: thumbnailUrl)
        let size = FileManager.default.fileSize(videoUrl.path)
        message.mediaUrl = videoFilename
        message.mediaDuration = Int64(phAsset.duration * 1000)
        message.mediaSize = size
        message.mediaMimeType = FileManager.default.mimeType(ext: ExtensionName.mp4.rawValue)
        MixinDatabase.shared.insertOrReplace(objects: [message])
        let change = ConversationChange(conversationId: message.conversationId,
                                        action: .updateMediaContent(messageId: message.messageId, message: message))
        NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: change)
    }
    
}
