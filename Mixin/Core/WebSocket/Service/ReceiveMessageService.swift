import Foundation
import UIKit
import SDWebImage
import UserNotifications

class ReceiveMessageService: MixinService {

    static let shared = ReceiveMessageService()

    private let processDispatchQueue = DispatchQueue(label: "one.mixin.messenger.queue.receive.messages")
    private let receiveDispatchQueue = DispatchQueue(label: "one.mixin.messenger.queue.receive")
    private let listPendingCallDelay = DispatchTimeInterval.seconds(2)
    private var listPendingCallWorkItems = [String: DispatchWorkItem]()
    private var listPendingCandidates = [String: [BlazeMessageData]]()
    
    let messageDispatchQueue = DispatchQueue(label: "one.mixin.messenger.queue.messages")
    var refreshRefreshOneTimePreKeys = [String: TimeInterval]()

    func receiveMessage(blazeMessage: BlazeMessage) {
        receiveDispatchQueue.async {
            guard let data = blazeMessage.data?.data(using: .utf8), let blazeMessageData = try? self.jsonDecoder.decode(BlazeMessageData.self, from: data) else {
                return
            }
            let messageId = blazeMessageData.messageId
            let status = blazeMessageData.status

            if blazeMessage.action == BlazeMessageAction.acknowledgeMessageReceipt.rawValue {
                MessageDAO.shared.updateMessageStatus(messageId: messageId, status: status)
                SendMessageService.shared.sendSessionMessage(action: .SEND_SESSION_MESSAGE, messageId: messageId, status: status)
                CryptoUserDefault.shared.statusOffset = blazeMessageData.updatedAt.toUTCDate().nanosecond()
            } else if blazeMessage.action == BlazeMessageAction.createMessage.rawValue || blazeMessage.action == BlazeMessageAction.createCall.rawValue {
                if blazeMessageData.userId == AccountAPI.shared.accountUserId && blazeMessageData.category.isEmpty {
                    MessageDAO.shared.updateMessageStatus(messageId: messageId, status: status)
                    SendMessageService.shared.sendSessionMessage(action: .SEND_SESSION_MESSAGE, messageId: messageId, status: status)
                } else {
                    guard BlazeMessageDAO.shared.insertOrReplace(messageId: messageId, conversationId: blazeMessageData.conversationId, data: data, createdAt: blazeMessageData.createdAt) else {
                        return
                    }
                    ReceiveMessageService.shared.processReceiveMessages()
                }
            } else if blazeMessage.action == BlazeMessageAction.createSessionMessage.rawValue {
                if blazeMessageData.userId == AccountAPI.shared.accountUserId && blazeMessageData.category.isEmpty && blazeMessageData.sessionId == AccountAPI.shared.accountSessionId {

                } else {
                    guard BlazeMessageDAO.shared.insertOrReplace(messageId: messageId, conversationId: blazeMessageData.conversationId, data: data, createdAt: blazeMessageData.createdAt) else {
                        return
                    }
                    ReceiveMessageService.shared.processReceiveMessages()
                }
            } else {
                ReceiveMessageService.shared.updateRemoteMessageStatus(messageId: messageId, status: .READ)
            }
        }
    }

    func processReceiveMessages() {
        guard !processing else {
            return
        }
        processing = true

        processDispatchQueue.async {
            defer {
                ReceiveMessageService.shared.processing = false
            }

            var finishedJobCount = 0

            repeat {
                let blazeMessageDatas = BlazeMessageDAO.shared.getBlazeMessageData(limit: 50)
                let remainJobCount = BlazeMessageDAO.shared.getCount()
                if remainJobCount + finishedJobCount > 500 {
                    let progress = blazeMessageDatas.count == 0 ? 100 : Int(Float(finishedJobCount) / Float(remainJobCount + finishedJobCount) * 100)
                    NotificationCenter.default.postOnMain(name: .SyncMessageDidAppear, object: progress)
                }
                guard blazeMessageDatas.count > 0 else {
                    return
                }

                for data in blazeMessageDatas {
                    guard AccountAPI.shared.didLogin else {
                        return
                    }
                    guard MessageCategory.isLegal(category: data.category) else {
                        ReceiveMessageService.shared.processBadMessage(data: data)
                        continue
                    }
                    if MessageDAO.shared.isExist(messageId: data.messageId) || MessageHistoryDAO.shared.isExist(messageId: data.messageId) {
                        ReceiveMessageService.shared.processBadMessage(data: data)
                        continue
                    }

                    ReceiveMessageService.shared.syncConversation(data: data)
                    if data.isSessionMessage {
                        ReceiveMessageService.shared.processSessionSystemMessage(data: data)
                        ReceiveMessageService.shared.processSessionPlainMessage(data: data)
                        ReceiveMessageService.shared.processSessionSignalMessage(data: data)
                        ReceiveMessageService.shared.processSessionRecallMessage(data: data)
                    } else {
                        ReceiveMessageService.shared.processSystemMessage(data: data)
                        ReceiveMessageService.shared.processPlainMessage(data: data)
                        ReceiveMessageService.shared.processSignalMessage(data: data)
                        ReceiveMessageService.shared.processAppButton(data: data)
                        ReceiveMessageService.shared.processWebRTCMessage(data: data)
                        ReceiveMessageService.shared.processRecallMessage(data: data)
                    }
                    BlazeMessageDAO.shared.delete(data: data)
                }

                finishedJobCount += blazeMessageDatas.count
            } while true
        }
    }

    private func processBadMessage(data: BlazeMessageData) {
        if data.isSessionMessage {
            SendMessageService.shared.sendSessionMessage(action: .SEND_SESSION_ACK_MESSAGE, messageId: data.messageId, status: MessageStatus.DELIVERED.rawValue)
        } else {
            ReceiveMessageService.shared.updateRemoteMessageStatus(messageId: data.messageId, status: .READ)
        }
        BlazeMessageDAO.shared.delete(data: data)
    }
    
    private func processWebRTCMessage(data: BlazeMessageData) {
        guard data.category.hasPrefix("WEBRTC_") else {
            return
        }
        _ = syncUser(userId: data.getSenderId())
        updateRemoteMessageStatus(messageId: data.messageId, status: .DELIVERED)
        MessageHistoryDAO.shared.replaceMessageHistory(messageId: data.messageId)
        if data.source == BlazeMessageAction.listPendingMessages.rawValue {
            if data.category == MessageCategory.WEBRTC_AUDIO_OFFER.rawValue {
                if abs(data.createdAt.toUTCDate().timeIntervalSinceNow) >= CallManager.unansweredTimeoutInterval {
                    let msg = Message.createWebRTCMessage(data: data, category: .WEBRTC_AUDIO_CANCEL, status: .DELIVERED)
                    MessageDAO.shared.insertMessage(message: msg, messageSource: data.source)
                } else {
                    let workItem = DispatchWorkItem(block: {
                        CallManager.shared.handleIncomingBlazeMessageData(data)
                        self.listPendingCallWorkItems.removeValue(forKey: data.messageId)
                        self.listPendingCandidates[data.messageId]?.forEach(CallManager.shared.handleIncomingBlazeMessageData)
                        self.listPendingCandidates = [:]
                    })
                    listPendingCallWorkItems[data.messageId] = workItem
                    DispatchQueue.global().asyncAfter(deadline: .now() + listPendingCallDelay, execute: workItem)
                }
            } else if let workItem = listPendingCallWorkItems[data.quoteMessageId] {
                let category = MessageCategory(rawValue: data.category) ?? .WEBRTC_AUDIO_FAILED
                if category == .WEBRTC_ICE_CANDIDATE {
                    if listPendingCandidates[data.quoteMessageId] == nil {
                        listPendingCandidates[data.quoteMessageId] = [data]
                    } else {
                        listPendingCandidates[data.quoteMessageId]!.append(data)
                    }
                } else if CallManager.completeCallCategories.contains(category) {
                    workItem.cancel()
                    listPendingCallWorkItems.removeValue(forKey: data.quoteMessageId)
                    listPendingCandidates.removeValue(forKey: data.quoteMessageId)
                    let msg = Message.createWebRTCMessage(messageId: data.quoteMessageId,
                                                          conversationId: data.conversationId,
                                                          userId: data.userId,
                                                          category: category,
                                                          status: .DELIVERED)
                    MessageDAO.shared.insertMessage(message: msg, messageSource: data.source)
                }
            } else {
                CallManager.shared.handleIncomingBlazeMessageData(data)
            }
        } else {
            CallManager.shared.handleIncomingBlazeMessageData(data)
        }
    }
    
    private func processAppButton(data: BlazeMessageData) {
        guard data.category == MessageCategory.APP_BUTTON_GROUP.rawValue || data.category == MessageCategory.APP_CARD.rawValue else {
            return
        }
        let message = Message.createMessage(appMessage: data)
        MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
        SendMessageService.shared.sendSessionMessage(message: message, data: data.data)
        updateRemoteMessageStatus(messageId: data.messageId, status: .READ)
    }

    private func processRecallMessage(data: BlazeMessageData) {
        guard data.category == MessageCategory.MESSAGE_RECALL.rawValue else {
            return
        }

        updateRemoteMessageStatus(messageId: data.messageId, status: .READ)
        MessageHistoryDAO.shared.replaceMessageHistory(messageId: data.messageId)

        if let base64Data = Data(base64Encoded: data.data), let plainData = (try? jsonDecoder.decode(TransferRecallData.self, from: base64Data)), !plainData.messageId.isEmpty, let message = MessageDAO.shared.getMessage(messageId: plainData.messageId) {
            MessageDAO.shared.recallMessage(message: message)
            SendMessageService.shared.sendRecallSessionMessage(messageId: plainData.messageId, conversationId: message.conversationId)
        }
    }

    private func processSignalMessage(data: BlazeMessageData) {
        guard data.category.hasPrefix("SIGNAL_") else {
            return
        }

        let username = UserDAO.shared.getUser(userId: data.userId)?.fullName ?? data.userId

        if data.category == MessageCategory.SIGNAL_KEY.rawValue {
            updateRemoteMessageStatus(messageId: data.messageId, status: .READ)
            MessageHistoryDAO.shared.replaceMessageHistory(messageId: data.messageId)
        } else {
            updateRemoteMessageStatus(messageId: data.messageId, status: .DELIVERED)
        }

        let decoded = SignalProtocol.shared.decodeMessageData(encoded: data.data)
        do {
            try SignalProtocol.shared.decrypt(groupId: data.conversationId, senderId: data.userId, keyType: decoded.keyType, cipherText: decoded.cipher, category: data.category, callback: { (plain) in
                if data.category != MessageCategory.SIGNAL_KEY.rawValue {
                    let plainText = String(data: plain, encoding: .utf8)!
                    if let messageId = decoded.resendMessageId {
                        self.processRedecryptMessage(data: data, messageId: messageId, plainText: plainText)
                        self.updateRemoteMessageStatus(messageId: data.messageId, status: .READ)
                        MessageHistoryDAO.shared.replaceMessageHistory(messageId: data.messageId)
                    } else {
                        self.processDecryptSuccess(data: data, plainText: plainText)
                    }
                }
            })
            let status = SignalProtocol.shared.getRatchetSenderKeyStatus(groupId: data.conversationId, senderId: data.userId)
            FileManager.default.writeLog(conversationId: data.conversationId, log: "[ProcessSignalMessage][\(username)][\(data.category)]...decrypt success...messageId:\(data.messageId)...\(data.createdAt)...status:\(status ?? "")...source:\(data.source)...resendMessageId:\(decoded.resendMessageId ?? "")")
            if status == RatchetStatus.REQUESTING.rawValue {
                SignalProtocol.shared.deleteRatchetSenderKey(groupId: data.conversationId, senderId: data.userId)
                self.requestResendMessage(conversationId: data.conversationId, userId: data.userId)
            }
        } catch {
            FileManager.default.writeLog(conversationId: data.conversationId, log: "[ProcessSignalMessage][\(username)][\(data.category)][\(CiphertextMessage.MessageType.toString(rawValue: decoded.keyType))]...decrypt failed...\(error)...messageId:\(data.messageId)...\(data.createdAt)...source:\(data.source)...resendMessageId:\(decoded.resendMessageId ?? "")")

            var userInfo = UIApplication.getTrackUserInfo()
            userInfo["conversationId"] = data.conversationId
            userInfo["keyType"] = CiphertextMessage.MessageType.toString(rawValue: decoded.keyType)
            userInfo["category"] = data.category
            userInfo["messageId"] = data.messageId
            userInfo["resendMessageId"] = decoded.resendMessageId ?? ""
            userInfo["source"] = data.source
            userInfo["error"] = "\(error)"
            userInfo["senderUserId"] = data.userId
            if let err = error as? SignalError {
                userInfo["signalErrorCode"] = "\(err.rawValue)"
            }
            if data.category == MessageCategory.SIGNAL_KEY.rawValue {
                userInfo["containsSession"] = "\(SignalProtocol.shared.containsSession(recipient: data.userId))"
                userInfo["sessionCount"] = "\(SessionDAO.shared.getCount())"
                userInfo["localIentity"] = IdentityDAO.shared.getLocalIdentity()?.address ?? ""
                userInfo["ratchetSenderKeyStatus"] =  SignalProtocol.shared.getRatchetSenderKeyStatus(groupId: data.conversationId, senderId: data.userId) ?? ""
            }
            userInfo["createdAt"] = data.createdAt
            UIApplication.traceErrorToFirebase(code: ReportErrorCode.decryptMessageError, userInfo: userInfo)

            guard !MessageDAO.shared.isExist(messageId: data.messageId) else {
                UIApplication.traceError(code: ReportErrorCode.receiveMessageError, userInfo: ["error": "duplicateMessage"])
                return
            }
            guard decoded.resendMessageId == nil else {
                return
            }
            if (data.category == MessageCategory.SIGNAL_KEY.rawValue) {
                SignalProtocol.shared.deleteRatchetSenderKey(groupId: data.conversationId, senderId: data.userId)
                refreshKeys(conversationId: data.conversationId)
            } else {
                insertFailedMessage(data: data)
                refreshKeys(conversationId: data.conversationId)
                let status = SignalProtocol.shared.getRatchetSenderKeyStatus(groupId: data.conversationId, senderId: data.userId)
                if status != RatchetStatus.REQUESTING.rawValue {
                    requestResendKey(conversationId: data.conversationId, userId: data.userId, messageId: data.messageId)
                    SignalProtocol.shared.setRatchetSenderKeyStatus(groupId: data.conversationId, senderId: data.userId, status: RatchetStatus.REQUESTING.rawValue)
                }
            }
        }
    }

    private func refreshKeys(conversationId: String) {
        let now = Date().timeIntervalSince1970
        guard now - (refreshRefreshOneTimePreKeys[conversationId] ?? 0) > 60 else {
            return
        }
        refreshRefreshOneTimePreKeys[conversationId] = now
        FileManager.default.writeLog(conversationId: conversationId, log: "[ProcessSignalMessage]...refreshKeys...")
        refreshKeys()
    }

    private func refreshKeys() {
        let countBlazeMessage = BlazeMessage(action: BlazeMessageAction.countSignalKeys.rawValue)
        guard let count = deliverKeys(blazeMessage: countBlazeMessage)?.toSignalKeyCount(), count.preKeyCount <= PreKeyUtil.prekeyMiniNum else {
            return
        }
        do {
            let request = try PreKeyUtil.generateKeys()
            let blazeMessage = BlazeMessage(params: BlazeMessageParam(syncSignalKeys: request), action: BlazeMessageAction.syncSignalKeys.rawValue)
            deliverNoThrow(blazeMessage: blazeMessage)
        } catch {
            UIApplication.traceError(error)
        }
    }
    
    private func processDecryptSuccess(data: BlazeMessageData, plainText: String, dataUserId: String? = nil) {
        if data.category.hasSuffix("_TEXT") {
            var content = plainText
            if data.category == MessageCategory.PLAIN_TEXT.rawValue {
                guard let decoded = plainText.base64Decoded() else {
                    return
                }
                content = decoded
            }
            let message = Message.createMessage(textMessage: content, data: data)
            MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
            SendMessageService.shared.sendSessionMessage(message: message, representativeId: dataUserId, data: content)
        } else if data.category.hasSuffix("_IMAGE") || data.category.hasSuffix("_VIDEO") {
            guard let base64Data = Data(base64Encoded: plainText), let transferMediaData = (try? jsonDecoder.decode(TransferAttachmentData.self, from: base64Data)) else {
                return
            }
            guard let height = transferMediaData.height, let width = transferMediaData.width, height > 0, width > 0, !(transferMediaData.mimeType?.isEmpty ?? true) else {
                return
            }
            let message = Message.createMessage(mediaData: transferMediaData, data: data)
            MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
            SendMessageService.shared.sendSessionMessage(message: message, representativeId: dataUserId, data: plainText)
        } else if data.category.hasSuffix("_LIVE") {
            guard let base64Data = Data(base64Encoded: plainText), let live = (try? jsonDecoder.decode(TransferLiveData.self, from: base64Data)) else {
                return
            }
            let message = Message.createMessage(liveData: live, data: data)
            MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
            SendMessageService.shared.sendSessionMessage(message: message, representativeId: dataUserId, data: plainText)
        } else if data.category.hasSuffix("_DATA")  {
            guard let base64Data = Data(base64Encoded: plainText), let transferMediaData = (try? jsonDecoder.decode(TransferAttachmentData.self, from: base64Data)) else {
                return
            }
            guard transferMediaData.size > 0 else {
                return
            }
            let message = Message.createMessage(mediaData: transferMediaData, data: data)
            MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
            SendMessageService.shared.sendSessionMessage(message: message, representativeId: dataUserId, data: plainText)
        } else if data.category.hasSuffix("_AUDIO") {
            guard let base64Data = Data(base64Encoded: plainText), let transferMediaData = (try? jsonDecoder.decode(TransferAttachmentData.self, from: base64Data)) else {
                return
            }
            let message = Message.createMessage(mediaData: transferMediaData, data: data)
            MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
            SendMessageService.shared.sendSessionMessage(message: message, representativeId: dataUserId, data: plainText)
            let job = AudioDownloadJob(messageId: message.messageId, mediaMimeType: message.mediaMimeType)
            ConcurrentJobQueue.shared.addJob(job: job)
        } else if data.category.hasSuffix("_STICKER") {
            guard let transferStickerData = parseSticker(plainText) else {
                return
            }
            let message = Message.createMessage(stickerData: transferStickerData, data: data)
            MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
            SendMessageService.shared.sendSessionMessage(message: message, representativeId: dataUserId, data: plainText)
        } else if data.category.hasSuffix("_CONTACT") {
            guard let base64Data = Data(base64Encoded: plainText), let transferData = (try? jsonDecoder.decode(TransferContactData.self, from: base64Data)) else {
                return
            }
            guard syncUser(userId: transferData.userId) else {
                return
            }
            let message = Message.createMessage(contactData: transferData, data: data)
            MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
            SendMessageService.shared.sendSessionMessage(message: message, representativeId: dataUserId, data: plainText)
        }
    }

    private func insertFailedMessage(data: BlazeMessageData) {
        guard data.category == MessageCategory.SIGNAL_TEXT.rawValue || data.category == MessageCategory.SIGNAL_IMAGE.rawValue || data.category == MessageCategory.SIGNAL_DATA.rawValue || data.category == MessageCategory.SIGNAL_VIDEO.rawValue || data.category == MessageCategory.SIGNAL_LIVE.rawValue || data.category == MessageCategory.SIGNAL_AUDIO.rawValue || data.category == MessageCategory.SIGNAL_CONTACT.rawValue || data.category == MessageCategory.SIGNAL_STICKER.rawValue else {
            return
        }
        var failedMessage = Message.createMessage(messageId: data.messageId, category: data.category, conversationId: data.conversationId, createdAt: data.createdAt, userId: data.userId)
        failedMessage.status = MessageStatus.FAILED.rawValue
        failedMessage.content = data.data
        failedMessage.quoteMessageId = data.quoteMessageId.isEmpty ? nil : data.quoteMessageId
        MessageDAO.shared.insertMessage(message: failedMessage, messageSource: data.source)
    }

    private func processRedecryptMessage(data: BlazeMessageData, messageId: String, plainText: String) {
        defer {
            let quoteMessageId = data.quoteMessageId
            if !quoteMessageId.isEmpty, let quoteContent = MessageDAO.shared.getQuoteMessage(messageId: quoteMessageId) {
                MessageDAO.shared.updateMessageQuoteContent(conversationId: data.conversationId, quoteMessageId: quoteMessageId, quoteContent: quoteContent)
            }
        }
        switch data.category {
        case MessageCategory.SIGNAL_TEXT.rawValue:
            MessageDAO.shared.updateMessageContentAndStatus(content: plainText, status: MessageStatus.DELIVERED.rawValue, messageId: messageId, category: data.category, conversationId: data.conversationId, messageSource: data.source)
            SendMessageService.shared.sendSessionMessage(message: Message.createMessage(textMessage: plainText, data: data), data: plainText)
        case MessageCategory.SIGNAL_IMAGE.rawValue, MessageCategory.SIGNAL_DATA.rawValue, MessageCategory.SIGNAL_VIDEO.rawValue, MessageCategory.SIGNAL_AUDIO.rawValue:
            guard let base64Data = Data(base64Encoded: plainText), let transferMediaData = (try? jsonDecoder.decode(TransferAttachmentData.self, from: base64Data)) else {
                return
            }
            MessageDAO.shared.updateMediaMessage(mediaData: transferMediaData, status: MessageStatus.DELIVERED.rawValue, messageId: messageId, category: data.category, conversationId: data.conversationId, mediaStatus: .PENDING, messageSource: data.source)
            if data.category == MessageCategory.SIGNAL_AUDIO.rawValue {
                let job = AudioDownloadJob(messageId: messageId, mediaMimeType: transferMediaData.mimeType)
                ConcurrentJobQueue.shared.addJob(job: job)
            }
            SendMessageService.shared.sendSessionMessage(message: Message.createMessage(mediaData: transferMediaData, data: data), data: plainText)
        case MessageCategory.SIGNAL_LIVE.rawValue:
            guard let base64Data = Data(base64Encoded: plainText), let liveData = (try? jsonDecoder.decode(TransferLiveData.self, from: base64Data)) else {
                return
            }
            MessageDAO.shared.updateLiveMessage(liveData: liveData, status:  MessageStatus.DELIVERED.rawValue, messageId: messageId, category: data.category, conversationId: data.conversationId, messageSource: data.source)
            SendMessageService.shared.sendSessionMessage(message: Message.createMessage(liveData: liveData, data: data), data: plainText)
        case MessageCategory.SIGNAL_STICKER.rawValue:
            guard let transferStickerData = parseSticker(plainText) else {
                return
            }
            MessageDAO.shared.updateStickerMessage(stickerData: transferStickerData, status: MessageStatus.DELIVERED.rawValue, messageId: messageId, category: data.category, conversationId: data.conversationId, messageSource: data.source)
            SendMessageService.shared.sendSessionMessage(message: Message.createMessage(stickerData: transferStickerData, data: data), data: plainText)
        case MessageCategory.SIGNAL_CONTACT.rawValue:
            guard let base64Data = Data(base64Encoded: plainText), let transferData = (try? jsonDecoder.decode(TransferContactData.self, from: base64Data)) else {
                return
            }
            guard syncUser(userId: transferData.userId) else {
                return
            }
            MessageDAO.shared.updateContactMessage(transferData: transferData, status: MessageStatus.DELIVERED.rawValue, messageId: messageId, category: data.category, conversationId: data.conversationId, messageSource: data.source)
            SendMessageService.shared.sendSessionMessage(message: Message.createMessage(contactData: transferData, data: data), data: plainText)
        default:
            break
        }
    }

    private func parseSticker(_ stickerText: String) -> TransferStickerData? {
        guard let base64Data = Data(base64Encoded: stickerText), let transferStickerData = (try? jsonDecoder.decode(TransferStickerData.self, from: base64Data)) else {
            return nil
        }

        if let stickerId = transferStickerData.stickerId, !stickerId.isEmpty {
            guard !StickerDAO.shared.isExist(stickerId: stickerId) else {
                return transferStickerData
            }

            repeat {
                switch StickerAPI.shared.sticker(stickerId: stickerId) {
                case let .success(sticker):
                    StickerDAO.shared.insertOrUpdateSticker(sticker: sticker)
                    if let sticker = StickerDAO.shared.getSticker(stickerId: sticker.stickerId) {
                        StickerPrefetcher.prefetch(stickers: [sticker])
                    }
                    return transferStickerData
                case let .failure(error):
                    guard error.code != 404 else {
                        return nil
                    }
                    checkNetworkAndWebSocket()
                }
            } while AccountAPI.shared.didLogin
            return nil
        } else if let stickerName = transferStickerData.name, let albumId = transferStickerData.albumId, let sticker = StickerDAO.shared.getSticker(albumId: albumId, name: stickerName) {
            return TransferStickerData(stickerId: sticker.stickerId, name: nil, albumId: nil)
        }
        return nil
    }

    private func syncConversation(data: BlazeMessageData) {
        guard data.conversationId != User.systemUser && data.conversationId != AccountAPI.shared.accountUserId else {
            return
        }
        if let status = ConversationDAO.shared.getConversationStatus(conversationId: data.conversationId) {
            if status == ConversationStatus.SUCCESS.rawValue || status == ConversationStatus.QUIT.rawValue {
                return
            } else if status == ConversationStatus.START.rawValue && ConversationDAO.shared.getConversationCategory(conversationId: data.conversationId) == ConversationCategory.GROUP.rawValue {
                // from NewGroupViewController
                return
            }
        } else {
            switch ConversationAPI.shared.getConversation(conversationId: data.conversationId) {
            case let .success(response):
                let userIds = response.participants
                    .map{ $0.userId }
                    .filter{ $0 != currentAccountId }
                var updatedUsers = true
                if userIds.count > 0 {
                    switch UserAPI.shared.showUsers(userIds: userIds) {
                    case let .success(users):
                        UserDAO.shared.updateUsers(users: users)
                    case .failure:
                        updatedUsers = false
                    }
                }
                if !ConversationDAO.shared.createConversation(conversation: response, targetStatus: .SUCCESS) || !updatedUsers {
                    ConcurrentJobQueue.shared.addJob(job: RefreshConversationJob(conversationId: data.conversationId))
                }
                return
            case .failure:
                ConversationDAO.shared.createPlaceConversation(conversationId: data.conversationId, ownerId: data.userId)
            }
        }
        ConcurrentJobQueue.shared.addJob(job: RefreshConversationJob(conversationId: data.conversationId))
    }

    @discardableResult
    private func checkUser(userId: String, tryAgain: Bool = false) -> ParticipantStatus {
        guard !userId.isEmpty else {
            return .ERROR
        }
        guard User.systemUser != userId, userId != currentAccountId, !UserDAO.shared.isExist(userId: userId) else {
            return .SUCCESS
        }
        switch UserAPI.shared.showUser(userId: userId) {
        case let .success(response):
            UserDAO.shared.updateUsers(users: [response])
            return .SUCCESS
        case let .failure(error):
            if tryAgain && error.code != 404 {
                ConcurrentJobQueue.shared.addJob(job: RefreshUserJob(userIds: [userId]))
            }
            return error.code == 404 ? .ERROR : .START
        }
    }

    private func syncUser(userId: String) -> Bool {
        guard !userId.isEmpty else {
            return false
        }
        guard User.systemUser != userId, userId != currentAccountId, !UserDAO.shared.isExist(userId: userId) else {
            return true
        }

        repeat {
            switch UserAPI.shared.showUser(userId: userId) {
            case let .success(response):
                UserDAO.shared.updateUsers(users: [response])
                return true
            case let .failure(error):
                guard error.code != 404 else {
                    return false
                }
                checkNetworkAndWebSocket()
            }
        } while AccountAPI.shared.didLogin

        return false
    }

    private func processPlainMessage(data: BlazeMessageData) {
        guard data.category.hasPrefix("PLAIN_") else {
            return
        }

        switch data.category {
        case MessageCategory.PLAIN_JSON.rawValue:
            defer {
                updateRemoteMessageStatus(messageId: data.messageId, status: .READ)
                MessageHistoryDAO.shared.replaceMessageHistory(messageId: data.messageId)
            }
            guard let base64Data = Data(base64Encoded: data.data), let plainData = (try? jsonDecoder.decode(TransferPlainData.self, from: base64Data)) else {
                return
            }

            if let user = UserDAO.shared.getUser(userId: data.userId) {
                FileManager.default.writeLog(conversationId: data.conversationId, log: "[ProcessPlainMessage][\(user.fullName)][\(data.category)][\(plainData.action)]...messageId:\(data.messageId)...\(data.createdAt)")
            }
            switch plainData.action {
            case PlainDataAction.RESEND_KEY.rawValue:
                guard SignalProtocol.shared.containsSession(recipient: data.userId) else {
                    return
                }
                SendMessageService.shared.sendMessage(conversationId: data.conversationId, userId: data.userId, action: .RESEND_KEY)
            case PlainDataAction.RESEND_MESSAGES.rawValue:
                guard let messageIds = plainData.messages, messageIds.count > 0 else {
                    return
                }
                SendMessageService.shared.resendMessages(conversationId: data.conversationId, userId: data.userId, messageIds: messageIds)
            case PlainDataAction.NO_KEY.rawValue:
                SignalProtocol.shared.deleteRatchetSenderKey(groupId: data.conversationId, senderId: data.userId)
            default:
                break
            }
        case MessageCategory.PLAIN_TEXT.rawValue, MessageCategory.PLAIN_IMAGE.rawValue, MessageCategory.PLAIN_DATA.rawValue, MessageCategory.PLAIN_VIDEO.rawValue, MessageCategory.PLAIN_LIVE.rawValue, MessageCategory.PLAIN_AUDIO.rawValue, MessageCategory.PLAIN_STICKER.rawValue, MessageCategory.PLAIN_CONTACT.rawValue:
            _ = syncUser(userId: data.getSenderId())
            processDecryptSuccess(data: data, plainText: data.data, dataUserId: data.getDataUserId())
            updateRemoteMessageStatus(messageId: data.messageId, status: .DELIVERED)
        default:
            break
        }
    }

    private func requestResendMessage(conversationId: String, userId: String) {
        let messages: [String] = MessageDAO.shared.findFailedMessages(conversationId: conversationId, userId: userId).reversed()
        guard messages.count > 0 else {
            SignalProtocol.shared.deleteRatchetSenderKey(groupId: conversationId, senderId: userId)
            return
        }

        FileManager.default.writeLog(conversationId: conversationId, log: "[ReceiveMessageService][REQUEST_REQUEST_MESSAGES]...messages:[\(messages.joined(separator: ","))]")
        let transferPlainData = TransferPlainData(action: PlainDataAction.RESEND_MESSAGES.rawValue, messageId: nil, messages: messages, status: nil)
        let encoded = (try? jsonEncoder.encode(transferPlainData).base64EncodedString()) ?? ""
        let messageId = UUID().uuidString.lowercased()
        let params = BlazeMessageParam(conversationId: conversationId, recipientId: userId, category: MessageCategory.PLAIN_JSON.rawValue, data: encoded, status: MessageStatus.SENDING.rawValue, messageId: messageId)
        let blazeMessage = BlazeMessage(params: params, action: BlazeMessageAction.createMessage.rawValue)
        SendMessageService.shared.sendMessage(conversationId: conversationId, userId: userId, blazeMessage: blazeMessage, action: .REQUEST_RESEND_MESSAGES)
    }

    private func requestResendKey(conversationId: String, userId: String, messageId: String) {
        let transferPlainData = TransferPlainData(action: PlainDataAction.RESEND_KEY.rawValue, messageId: messageId, messages: nil, status: nil)
        let encoded = (try? jsonEncoder.encode(transferPlainData).base64EncodedString()) ?? ""
        let messageId = UUID().uuidString.lowercased()
        let params = BlazeMessageParam(conversationId: conversationId, recipientId: userId, category: MessageCategory.PLAIN_JSON.rawValue, data: encoded, status: MessageStatus.SENDING.rawValue, messageId: messageId)
        let blazeMessage = BlazeMessage(params: params, action: BlazeMessageAction.createMessage.rawValue)
        SendMessageService.shared.sendMessage(conversationId: conversationId, userId: userId, blazeMessage: blazeMessage, action: .REQUEST_RESEND_KEY)
    }

    private func updateRemoteMessageStatus(messageId: String, status: MessageStatus) {
        SendMessageService.shared.sendAckMessage(messageId: messageId, status: status)
    }
}

extension ReceiveMessageService {

    private func processSystemMessage(data: BlazeMessageData) {
        guard data.category.hasPrefix("SYSTEM_") else {
            return
        }

        switch data.category {
        case MessageCategory.SYSTEM_CONVERSATION.rawValue:
            messageDispatchQueue.sync {
                processSystemConversationMessage(data: data)
            }
        case MessageCategory.SYSTEM_ACCOUNT_SNAPSHOT.rawValue:
            processSystemSnapshotMessage(data: data)
        default:
            break
        }
        updateRemoteMessageStatus(messageId: data.messageId, status: .READ)
    }

    private func processSystemSnapshotMessage(data: BlazeMessageData) {
        guard let base64Data = Data(base64Encoded: data.data), let snapshot = (try? jsonDecoder.decode(Snapshot.self, from: base64Data)) else {
            return
        }

        if let opponentId = snapshot.opponentId {
            checkUser(userId: opponentId, tryAgain: true)
        }

        switch AssetAPI.shared.asset(assetId: snapshot.assetId) {
        case let .success(asset):
            AssetDAO.shared.insertOrUpdateAssets(assets: [asset])
        case .failure:
            ConcurrentJobQueue.shared.addJob(job: RefreshAssetsJob(assetId: snapshot.assetId))
        }

        if snapshot.type == SnapshotType.deposit.rawValue, let transactionHash = snapshot.transactionHash {
            SnapshotDAO.shared.removePendingDeposits(assetId: snapshot.assetId, transactionHash: transactionHash)
        }

        SnapshotDAO.shared.insertOrReplaceSnapshots(snapshots: [snapshot])
        let message = Message.createMessage(snapshotMesssage: snapshot, data: data)
        MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
        SendMessageService.shared.sendSessionMessage(message: message, data: data.data)
    }

    private func processSystemConversationMessage(data: BlazeMessageData) {
        guard let base64Data = Data(base64Encoded: data.data), let sysMessage = (try? jsonDecoder.decode(SystemConversationData.self, from: base64Data)) else {
            return
        }

        let userId = sysMessage.userId ?? data.userId
        let messageId = data.messageId
        var operSuccess = true

        if let participantId = sysMessage.participantId {
            let usernameOrId = UserDAO.shared.getUser(userId: participantId)?.fullName ?? participantId
            FileManager.default.writeLog(conversationId: data.conversationId, log: "[ProcessSystemMessage][\(usernameOrId)][\(sysMessage.action)]...messageId:\(data.messageId)...\(data.createdAt)")
        }

        if (userId == User.systemUser) {
            UserDAO.shared.insertSystemUser(userId: userId)
        }

        let message = Message.createMessage(systemMessage: sysMessage.action, participantId: sysMessage.participantId, userId: userId, data: data)

        defer {
            if operSuccess {
                SendMessageService.shared.sendSessionMessage(message: message, data: data.data)
                if sysMessage.action != SystemConversationAction.UPDATE.rawValue && sysMessage.action != SystemConversationAction.ROLE.rawValue {
                    ConcurrentJobQueue.shared.addJob(job: RefreshGroupIconJob(conversationId: data.conversationId))
                }
            }
        }
        
        switch sysMessage.action {
        case SystemConversationAction.ADD.rawValue, SystemConversationAction.JOIN.rawValue:
            guard let participantId = sysMessage.participantId, !participantId.isEmpty, participantId != User.systemUser else {
                return
            }
            let status = checkUser(userId: participantId, tryAgain: true)
            operSuccess = ParticipantDAO.shared.addParticipant(message: message, conversationId: data.conversationId, participantId: participantId, updatedAt: data.updatedAt, status: status, source: data.source)

            if participantId != currentAccountId && SignalProtocol.shared.isExistSenderKey(groupId: data.conversationId, senderId: currentAccountId) {
                SendMessageService.shared.sendMessage(conversationId: data.conversationId, userId: participantId, action: .SEND_KEY)
            }
            return
        case SystemConversationAction.REMOVE.rawValue:
            guard let participantId = sysMessage.participantId, !participantId.isEmpty, participantId != User.systemUser else {
                return
            }
            SignalProtocol.shared.clearSenderKey(groupId: data.conversationId, senderId: currentAccountId)
            SentSenderKeyDAO.shared.delete(byConversationId: data.conversationId)

            operSuccess = ParticipantDAO.shared.removeParticipant(message: message, conversationId: data.conversationId, userId: participantId, source: data.source)
             ConcurrentJobQueue.shared.addJob(job: RefreshUserJob(userIds: [participantId]))
            return
        case SystemConversationAction.EXIT.rawValue:
            guard let participantId = sysMessage.participantId, !participantId.isEmpty, participantId != User.systemUser else {
                return
            }

            SignalProtocol.shared.clearSenderKey(groupId: data.conversationId, senderId: currentAccountId)
            SentSenderKeyDAO.shared.delete(byConversationId: data.conversationId)

            guard participantId != currentAccountId else {
                ConversationDAO.shared.deleteAndExitConversation(conversationId: data.conversationId, autoNotification: false)
                return
            }

            operSuccess = ParticipantDAO.shared.removeParticipant(message: message, conversationId: data.conversationId, userId: participantId, source: data.source)
            return
        case SystemConversationAction.CREATE.rawValue:
            checkUser(userId: userId, tryAgain: true)
            operSuccess = ConversationDAO.shared.updateConversationOwnerId(conversationId: data.conversationId, ownerId: userId)
        case SystemConversationAction.ROLE.rawValue:
            guard let participantId = sysMessage.participantId, !participantId.isEmpty, participantId != User.systemUser, let role = sysMessage.role else {
                return
            }
            operSuccess = ParticipantDAO.shared.updateParticipantRole(message: message, conversationId: data.conversationId, participantId: participantId, role: role, source: data.source)
            return
        case SystemConversationAction.UPDATE.rawValue:
            ConcurrentJobQueue.shared.addJob(job: RefreshConversationJob(conversationId: data.conversationId))
            return
        default:
            break
        }

        MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
    }
}

extension CiphertextMessage.MessageType {

    static func toString(rawValue: UInt8) -> String {
        switch rawValue {
        case CiphertextMessage.MessageType.preKey.rawValue:
            return "preKey"
        case CiphertextMessage.MessageType.senderKey.rawValue:
            return "senderKey"
        case CiphertextMessage.MessageType.signal.rawValue:
            return "signal"
        case CiphertextMessage.MessageType.distribution.rawValue:
            return "distribution"
        default:
            return "unknown"
        }
    }
}

extension ReceiveMessageService {

    private func processSessionRecallMessage(data: BlazeMessageData) {
        guard data.isSessionMessage, data.category == MessageCategory.MESSAGE_RECALL.rawValue else {
            return
        }
        SendMessageService.shared.sendSessionMessage(action: .SEND_SESSION_ACK_MESSAGE, messageId: data.messageId, status: MessageStatus.DELIVERED.rawValue)

        guard let base64Data = Data(base64Encoded: data.data), let plainData = (try? jsonDecoder.decode(TransferRecallData.self, from: base64Data)), !plainData.messageId.isEmpty else {
            return
        }
        guard let message = MessageDAO.shared.getMessage(messageId: plainData.messageId) else {
            return
        }
        SendMessageService.shared.recallMessage(messageId: message.messageId, category: message.category, mediaUrl: message.mediaUrl, conversationId: message.conversationId, status: message.status, sendToSession: false)
    }

    private func processSessionPlainMessage(data: BlazeMessageData) {
        guard data.isSessionMessage, data.category.hasPrefix("PLAIN_") else {
            return
        }
        
        switch data.category {
        case MessageCategory.PLAIN_JSON.rawValue:
            guard let base64Data = Data(base64Encoded: data.data), let plainData = (try? jsonDecoder.decode(TransferPlainAckData.self, from: base64Data)) else {
                SendMessageService.shared.sendSessionMessage(action: .SEND_SESSION_ACK_MESSAGE, messageId: data.messageId, status: MessageStatus.READ.rawValue)
                return
            }
            if plainData.action == PlainDataAction.ACKNOWLEDGE_MESSAGE_RECEIPTS.rawValue {
                for message in plainData.messages {
                    guard message.status == MessageStatus.READ.rawValue else {
                        continue
                    }
                    if MessageDAO.shared.updateMessageStatus(messageId: message.messageId, status: MessageStatus.READ.rawValue, updateUnseen: true) {
                        ReceiveMessageService.shared.updateRemoteMessageStatus(messageId: message.messageId, status: .READ)
                        UNUserNotificationCenter.current().removeNotifications(identifier: message.messageId)
                    }
                }
                ConversationDAO.shared.showBadgeNumber()
                SendMessageService.shared.sendSessionMessage(action: .SEND_SESSION_ACK_MESSAGE, messageId: data.messageId, status: MessageStatus.DELIVERED.rawValue)
            }
        case MessageCategory.PLAIN_TEXT.rawValue, MessageCategory.PLAIN_IMAGE.rawValue, MessageCategory.PLAIN_DATA.rawValue, MessageCategory.PLAIN_VIDEO.rawValue, MessageCategory.PLAIN_LIVE.rawValue, MessageCategory.PLAIN_AUDIO.rawValue, MessageCategory.PLAIN_STICKER.rawValue, MessageCategory.PLAIN_CONTACT.rawValue:
            _ = syncUser(userId: data.getSenderId())
            processSessionDecryptSuccess(data: data, plainText: data.data)
            SendMessageService.shared.sendSessionMessage(action: .SEND_SESSION_ACK_MESSAGE, messageId: data.messageId, status: MessageStatus.DELIVERED.rawValue)
        default:
            break
        }
    }

    private func processSessionSignalMessage(data: BlazeMessageData) {
        guard data.isSessionMessage, data.category.hasPrefix("SIGNAL_") else {
            return
        }

        let decoded = SignalProtocol.shared.decodeMessageData(encoded: data.data)
        let deviceId = data.sessionId?.hashCode() ?? SignalProtocol.shared.DEFAULT_DEVICE_ID
        do {
            try SignalProtocol.shared.decrypt(groupId: data.conversationId, senderId: data.userId, keyType: decoded.keyType, cipherText: decoded.cipher, category: data.category, deviceId: deviceId, callback: { (plain) in
                let plainText = String(data: plain, encoding: .utf8)!
                var blazeMessageData = data
                if let userId = data.primitiveId {
                    blazeMessageData.userId = userId
                }
                self.processSessionDecryptSuccess(data: blazeMessageData, plainText: plainText)
            })
        } catch {
            FileManager.default.writeLog(conversationId: data.conversationId, log: "[ProcessSignalMessage][\(data.category)][processSessionSignalMessage][\(CiphertextMessage.MessageType.toString(rawValue: decoded.keyType))]...decrypt failed...\(error)...messageId:\(data.messageId)...\(data.createdAt)...source:\(data.source)")
            insertFailedMessage(data: data)
        }
        SendMessageService.shared.sendSessionMessage(action: .SEND_SESSION_ACK_MESSAGE, messageId: data.messageId, status: MessageStatus.DELIVERED.rawValue)
    }

    private func processSessionSystemMessage(data: BlazeMessageData) {
        guard data.isSessionMessage, data.category.hasPrefix("SYSTEM_") else {
            return
        }

        switch data.category {
        case MessageCategory.SYSTEM_EXTENSION_SESSION.rawValue:
            processSessionSystemConversationMessage(data: data)
        default:
            break
        }
        SendMessageService.shared.sendSessionMessage(action: .SEND_SESSION_ACK_MESSAGE, messageId: data.messageId, status: MessageStatus.DELIVERED.rawValue)
    }

    private func processSessionSystemConversationMessage(data: BlazeMessageData) {
        guard let base64Data = Data(base64Encoded: data.data), let sysMessage = (try? jsonDecoder.decode(SystemConversationData.self, from: base64Data)) else {
            return
        }
        guard let sessionId = data.sessionId else {
            return
        }

        switch sysMessage.action {
        case SystemConversationAction.ADD_SESSION.rawValue:
            AccountUserDefault.shared.lastDesktopLogin = Date()
            AccountUserDefault.shared.extensionSession = sessionId
            SignalProtocol.shared.deleteSession(userId: data.userId)
            NotificationCenter.default.postOnMain(name: .UserSessionDidChange)
        case SystemConversationAction.REMOVE_SESSION.rawValue:
            guard let extensionSession = AccountUserDefault.shared.extensionSession, extensionSession == sessionId else {
                return
            }
            AccountUserDefault.shared.extensionSession = nil
            SignalProtocol.shared.deleteSession(userId: data.userId)
            JobDAO.shared.clearSessionJob()
            NotificationCenter.default.postOnMain(name: .UserSessionDidChange)
        default:
            break
        }
    }

    private func processSessionDecryptSuccess(data: BlazeMessageData, plainText: String) {
        if data.category.hasSuffix("_TEXT") {
            var content = plainText
            if data.category == MessageCategory.PLAIN_TEXT.rawValue {
                guard let decoded = plainText.base64Decoded() else {
                    return
                }
                content = decoded
            }
            var message = Message.createMessage(textMessage: content, data: data)
            message.status = MessageStatus.SENDING.rawValue
            MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
            SendMessageService.shared.sendMessage(message: message, data: content)
        } else if data.category.hasSuffix("_STICKER") {
            guard let transferStickerData = parseSticker(plainText) else {
                return
            }
            var message = Message.createMessage(stickerData: transferStickerData, data: data)
            message.status = MessageStatus.SENDING.rawValue
            MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
            SendMessageService.shared.sendMessage(message: message, data: plainText)
        } else if data.category.hasSuffix("_IMAGE") {
            guard let base64Data = Data(base64Encoded: plainText), let transferMediaData = (try? jsonDecoder.decode(TransferAttachmentData.self, from: base64Data)) else {
                return
            }
            guard let height = transferMediaData.height, let width = transferMediaData.width, height > 0, width > 0, !(transferMediaData.mimeType?.isEmpty ?? true) else {
                return
            }
            var message = Message.createMessage(mediaData: transferMediaData, data: data)
            message.status = MessageStatus.SENDING.rawValue
            MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
            SendMessageService.shared.sendMessage(message: message, data: plainText)
        } else if data.category.hasSuffix("_DATA") {
            guard let base64Data = Data(base64Encoded: plainText), let transferMediaData = (try? jsonDecoder.decode(TransferAttachmentData.self, from: base64Data)) else {
                return
            }
            guard transferMediaData.size > 0 else {
                return
            }
            let message = Message.createMessage(mediaData: transferMediaData, data: data)
            MessageDAO.shared.insertMessage(message: message, messageSource: data.source)
            SendMessageService.shared.sendMessage(message: message, data: plainText)
        }
    }

}
