import Foundation

class CommonUserDefault {

    static let shared = CommonUserDefault()
    
    static let didChangeRecentlyUsedAppIdsNotification = Notification.Name(rawValue: "one.mixin.ios.recently.used.app.ids.change")
    
    private let keyFirstLaunchSince1970 = "first_launch_since_1970"
    private let keyHasPerformedTransfer = "has_performed_transfer"
    private var keyConversationDraft: String {
        return "defalut_conversation_draft_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyLastUpdateOrInstallVersion: String {
        return "last_update_or_install_version_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyLastUpdateOrInstallDate: String {
        return "last_update_or_install_date_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyHasUnreadAnnouncement: String {
        return "default_unread_announcement_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyCameraQRCodeTips: String {
        return "default_camera_qrcode_tips_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyHasPerformedQRCodeScanning : String {
        return "has_scanned_qr_code_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyMessageNotificationShowPreview: String {
        return "msg_notification_preview_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyBackupVideos: String {
        return "backup_videos_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyBackupFiles: String {
        return "backup_files_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyBackupCategory: String {
        return "backup_category_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyLastBackupTime: String {
        return "last_backup_time_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyLastBackupSize: String {
        return "last_backup_size_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyHasForceLogout: String {
        return "has_force_logout_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyRecentlyUsedAppIds: String {
        return "recently_used_app_ids_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyRecallTips: String {
        return "default_recall_tips_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyAutoDownloadPhotos: String {
        return "auto_download_photos_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyAutoDownloadVideos: String {
        return "auto_download_videos_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyAutoDownloadFiles: String {
        return "auto_download_files_\(AccountAPI.shared.accountIdentityNumber)"
    }
    private var keyUploadContacts: String {
        return "auto_upload_contacts_\(AccountAPI.shared.accountIdentityNumber)"
    }
    
    enum BackupCategory: String {
        case daily
        case weekly
        case monthly
        case off
    }
    
    enum AutoDownload: Int {
        case never = 0
        case wifi
        case wifiAndCellular
        
        var description: String {
            switch self {
            case .never:
                return R.string.localizable.setting_auto_download_never()
            case .wifi:
                return R.string.localizable.setting_auto_download_wifi()
            case .wifiAndCellular:
                return R.string.localizable.setting_auto_download_wifi_cellular()
            }
        }
    }
    
    private let session = UserDefaults(suiteName: SuiteName.common)!

    var isUploadContacts: Bool {
        get {
            if session.object(forKey: keyUploadContacts) != nil {
                return session.bool(forKey: keyUploadContacts)
            } else {
                return ContactsManager.shared.authorization == .authorized
            }
        }
        set {
            session.set(newValue, forKey: keyUploadContacts)
        }
    }
    
    var isRecallTips: Bool {
        get {
            return session.bool(forKey: keyRecallTips)
        }
        set {
            session.set(newValue, forKey: keyRecallTips)
        }
    }

    var isCameraQRCodeTips: Bool {
        get {
            return session.bool(forKey: keyCameraQRCodeTips)
        }
        set {
            session.set(newValue, forKey: keyCameraQRCodeTips)
        }
    }

    var hasPerformedQRCodeScanning: Bool {
        get {
            return session.bool(forKey: keyHasPerformedQRCodeScanning)
        }
        set {
            session.set(newValue, forKey: keyHasPerformedQRCodeScanning)
        }
    }
    
    var hasPerformedTransfer: Bool {
        get {
            return session.bool(forKey: keyHasPerformedTransfer)
        }
        set {
            session.set(newValue, forKey: keyHasPerformedTransfer)
        }
    }

    var hasBackupVideos: Bool {
        get {
            return session.bool(forKey: keyBackupVideos)
        }
        set {
            session.set(newValue, forKey: keyBackupVideos)
        }
    }

    var hasForceLogout: Bool {
        get {
            return session.bool(forKey: keyHasForceLogout)
        }
        set {
            session.set(newValue, forKey: keyHasForceLogout)
        }
    }

    var hasBackupFiles: Bool {
        get {
            return session.bool(forKey: keyBackupFiles)
        }
        set {
            session.set(newValue, forKey: keyBackupFiles)
        }
    }

    var lastBackupTime: TimeInterval {
        get {
            return session.double(forKey: keyLastBackupTime)
        }
        set {
            session.set(newValue, forKey: keyLastBackupTime)
        }
    }

    var lastBackupSize: Int64? {
        get {

            return session.object(forKey: keyLastBackupSize) as? Int64
        }
        set {
            session.set(newValue, forKey: keyLastBackupSize)
        }
    }


    var backupCategory: BackupCategory {
        get {
            guard let category = session.string(forKey: keyBackupCategory) else {
                return .off
            }
            return BackupCategory(rawValue: category) ?? .off
        }
        set {
            session.set(newValue.rawValue, forKey: keyBackupCategory)
        }
    }

    var shouldShowPreviewForMessageNotification: Bool {
        get {
            if session.object(forKey: keyMessageNotificationShowPreview) != nil {
                return session.bool(forKey: keyMessageNotificationShowPreview)
            } else {
                return true
            }
        }
        set {
            session.set(newValue, forKey: keyMessageNotificationShowPreview)
        }
    }
    
    private var conversationDraft: [String: Any] {
        get {
            return session.dictionary(forKey: keyConversationDraft) ?? [:]
        }
        set {
            session.set(newValue, forKey: keyConversationDraft)
        }
    }

    private var hasUnreadAnnouncement: [String: Bool] {
        get {
            return (session.dictionary(forKey: keyHasUnreadAnnouncement) as? [String : Bool]) ?? [:]
        }
        set {
            session.set(newValue, forKey: keyHasUnreadAnnouncement)
        }
    }
    
    func getConversationDraft(_ conversationId: String) -> String? {
        return conversationDraft[conversationId] as? String
    }

    func setConversationDraft(_ conversationId: String, draft: String) {
        if draft.isEmpty {
            conversationDraft.removeValue(forKey: conversationId)
        } else {
            conversationDraft[conversationId] = draft
        }
    }

    var lastUpdateOrInstallVersion: String? {
        return session.string(forKey: keyLastUpdateOrInstallVersion)
    }

    func checkUpdateOrInstallVersion() {
        let lastVersion = lastUpdateOrInstallVersion
        if lastVersion != Bundle.main.bundleVersion {
            if AccountAPI.shared.didLogin && !(lastVersion?.isEmpty ?? true) {
                let previousUpdateOrInstallTime = CommonUserDefault.shared.lastUpdateOrInstallTime
                DispatchQueue.global().async {
                    if IdentityDAO.shared.getCount() == 0 {
                        FileManager.default.writeLog(log: "[AppUpgrade]sessionCount:\(SessionDAO.shared.getCount())...identityCount:0")
                        var userInfo = [String: Any]()
                        userInfo["didLogin"] = AccountAPI.shared.didLogin
                        userInfo["previousUpdateOrInstallTime"] = previousUpdateOrInstallTime
                        userInfo["newUpdateOrInstallTime"] = Date().toUTCString()
                        userInfo["identityCount"] = "0"
                        userInfo["oldVersion"] = lastVersion ?? ""
                        userInfo["newVersion"] = Bundle.main.bundleVersion
                        UIApplication.traceError(code: ReportErrorCode.appUpgradeError, userInfo: userInfo)
                    }
                }
            }
            session.set(Bundle.main.bundleVersion, forKey: keyLastUpdateOrInstallVersion)
            session.set(Date().toUTCString(), forKey: keyLastUpdateOrInstallDate)
        }
    }

    var firstLaunchTimeIntervalSince1970: TimeInterval {
        return session.double(forKey: keyFirstLaunchSince1970)
    }
    
    func updateFirstLaunchDateIfNeeded() {
        guard session.double(forKey: keyFirstLaunchSince1970) == 0 else {
            return
        }
        session.set(Date().timeIntervalSince1970, forKey: keyFirstLaunchSince1970)
    }
    
    var lastUpdateOrInstallTime: String {
        return session.string(forKey: keyLastUpdateOrInstallDate) ?? Date().toUTCString()
    }

    func hasUnreadAnnouncement(conversationId: String) -> Bool {
        return hasUnreadAnnouncement[conversationId] ?? false
    }
    
    func setHasUnreadAnnouncement(_ hasUnreadAnnouncement: Bool, forConversationId conversationId: String) {
        guard !conversationId.isEmpty else {
            return
        }
        self.hasUnreadAnnouncement[conversationId] = hasUnreadAnnouncement
    }
    
    private(set) var recentlyUsedAppIds: [String] {
        get {
            return session.stringArray(forKey: keyRecentlyUsedAppIds) ?? []
        }
        set {
            session.set(newValue, forKey: keyRecentlyUsedAppIds)
        }
    }
    
    func insertRecentlyUsedAppId(id: String) {
        let maxNumberOfIds = 12
        var ids = recentlyUsedAppIds
        ids.removeAll(where: { $0 == id })
        ids.insert(id, at: 0)
        if ids.count > maxNumberOfIds {
            ids.removeLast(ids.count - maxNumberOfIds)
        }
        recentlyUsedAppIds = ids
        NotificationCenter.default.post(name: CommonUserDefault.didChangeRecentlyUsedAppIdsNotification, object: ids)
    }
    
    var autoDownloadPhotos: AutoDownload {
        get {
            if let value = session.object(forKey: keyAutoDownloadPhotos) as? Int, let status = AutoDownload(rawValue: value) {
                return status
            } else {
                return .wifiAndCellular
            }
        }
        set {
            session.set(newValue.rawValue, forKey: keyAutoDownloadPhotos)
        }
    }
    
    var autoDownloadVideos: AutoDownload {
        get {
            if let value = session.object(forKey: keyAutoDownloadVideos) as? Int, let status = AutoDownload(rawValue: value) {
                return status
            } else {
                return .never
            }
        }
        set {
            session.set(newValue.rawValue, forKey: keyAutoDownloadVideos)
        }
    }
    
    var autoDownloadFiles: AutoDownload {
        get {
            if let value = session.object(forKey: keyAutoDownloadFiles) as? Int, let status = AutoDownload(rawValue: value) {
                return status
            } else {
                return .never
            }
        }
        set {
            session.set(newValue.rawValue, forKey: keyAutoDownloadFiles)
        }
    }
    
}
