import UIKit
import Bugsnag
import UserNotifications
import Firebase
import SDWebImage
import YYImage
import GiphyCoreSDK
import PushKit
import Crashlytics

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    static var current: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }
    
    let window = UIWindow(frame: UIScreen.main.bounds)
    
    private(set) var voipToken = ""
    
    private var autoCanceleNotification: DispatchWorkItem?
    private var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
    private var backgroundTime: Timer?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if RELEASE
        initBugsnag()
        #endif
        FirebaseApp.configure()
        updateSharedImageCacheConfig()
        NetworkManager.shared.startListening()
        UNUserNotificationCenter.current().registerNotificationCategory()
        UNUserNotificationCenter.current().delegate = self
        let pkpushRegistry = PKPushRegistry(queue: DispatchQueue.main)
        pkpushRegistry.delegate = self
        pkpushRegistry.desiredPushTypes = [.voIP]
        checkLogin()
        checkJailbreak()
        configAnalytics()
        if let key = MixinKeys.giphy {
            GiphyCore.configure(apiKey: key)
        }
        FileManager.default.writeLog(log: "\n-----------------------\nAppDelegate...didFinishLaunching...isProtectedDataAvailable:\(UIApplication.shared.isProtectedDataAvailable)...\(Bundle.main.shortVersion)(\(Bundle.main.bundleVersion))")
        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        AudioManager.shared.pause()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        checkServerData()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        UNUserNotificationCenter.current().removeAllNotifications()
        WebSocketService.shared.checkConnectStatus()
        cancelBackgroundTask()

        if let conversationId = UIApplication.currentConversationId() {
            SendMessageService.shared.sendReadMessages(conversationId: conversationId)
        }
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        MixinDatabase.shared.close()
        SignalDatabase.shared.close()
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AccountAPI.shared.updateSession(deviceToken: deviceToken.toHexString(), voip_token: "")
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.newData)
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return AccountAPI.shared.didLogin && UrlWindow.checkUrl(url: url)
    }
    
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        guard AccountAPI.shared.account == nil else {
            return
        }
        guard let account = AccountUserDefault.shared.getAccount() else {
            return
        }

        AccountAPI.shared.account = account
        configAnalytics()
        if AccountAPI.shared.didLogin && !(window.rootViewController is HomeContainerViewController) {
            checkLogin()
        }
    }
    
}

extension AppDelegate: PKPushRegistryDelegate {
    
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        voipToken = pushCredentials.token.toHexString()
        if AccountAPI.shared.didLogin {
            AccountAPI.shared.updateSession(deviceToken: "", voip_token: voipToken)
        }
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        checkServerData(isPushKit: true)
    }
    
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if !handerQuickAction(response) {
            dealWithRemoteNotification(response.notification.request.content.userInfo)
        }
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        if userInfo["fromWebSocket"] as? Bool ?? false {
            completionHandler([.alert, .sound])
            autoCanceleNotification?.cancel()
            let workItem = DispatchWorkItem(block: {
                guard let workItem = UIApplication.appDelegate().autoCanceleNotification, !workItem.isCancelled else {
                    return
                }
                guard AccountAPI.shared.didLogin else {
                    return
                }
                UNUserNotificationCenter.current().removeNotifications(identifier: NotificationRequestIdentifier.showInApp)
            })
            self.autoCanceleNotification = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3), execute: workItem)
        } else {
            completionHandler([])
        }
    }
    
}

extension AppDelegate {
    
    func handerQuickAction(_ response: UNNotificationResponse) -> Bool {
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let actionIdentifier = response.actionIdentifier
        let inputText = (response as? UNTextInputNotificationResponse)?.userText
        let userInfo = response.notification.request.content.userInfo
        return handerQuickAction(categoryIdentifier: categoryIdentifier, actionIdentifier: actionIdentifier, inputText: inputText, userInfo: userInfo)
    }
    
    @discardableResult
    func handerQuickAction(categoryIdentifier: String, actionIdentifier: String, inputText: String?, userInfo: [AnyHashable : Any]) -> Bool {
        guard categoryIdentifier == NotificationCategoryIdentifier.message, AccountAPI.shared.didLogin else {
            return false
        }

        guard let conversationId = userInfo["conversation_id"] as? String, let conversationCategory = userInfo["conversation_category"] as? String else {
            return false
        }

        switch actionIdentifier {
        case NotificationActionIdentifier.reply:
            guard let text = inputText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return false
            }
            var ownerUser: UserItem?
            if let userId = userInfo["user_id"] as? String, let userFullName = userInfo["userFullName"] as? String, let userAvatarUrl = userInfo["userAvatarUrl"] as? String, let userIdentityNumber = userInfo["userIdentityNumber"] as? String {
                ownerUser = UserItem.createUser(userId: userId, fullName: userFullName, identityNumber: userIdentityNumber, avatarUrl: userAvatarUrl, appId: userInfo["userAppId"] as? String)
            }
            var newMsg = Message.createMessage(category: MessageCategory.SIGNAL_TEXT.rawValue, conversationId: conversationId, createdAt: Date().toUTCString(), userId: AccountAPI.shared.accountUserId)
            newMsg.content = text
            newMsg.quoteMessageId = userInfo["message_id"] as? String
            DispatchQueue.global().async {
                SendMessageService.shared.sendMessage(message: newMsg, ownerUser: ownerUser, isGroupMessage: conversationCategory == ConversationCategory.GROUP.rawValue)
                SendMessageService.shared.sendReadMessages(conversationId: conversationId, force: true)
            }
        default:
            return false
        }
        return true
    }
    
}

extension AppDelegate {
    
    private func checkLogin() {
        window.backgroundColor = .black
        if AccountAPI.shared.didLogin {
            window.rootViewController = makeInitialViewController()
            if ContactsManager.shared.authorization == .authorized && CommonUserDefault.shared.isUploadContacts {
                DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: {
                    PhoneContactAPI.shared.upload(contacts: ContactsManager.shared.contacts)
                })
            }
        } else {
            if UIApplication.shared.isProtectedDataAvailable {
                window.rootViewController = LoginNavigationController.instance()
            } else {
                window.rootViewController = R.storyboard.launchScreen().instantiateInitialViewController()
            }
        }
        window.makeKeyAndVisible()
    }
    
    private func configAnalytics() {
        guard UIApplication.shared.isProtectedDataAvailable else {
            return
        }

        if let account = AccountAPI.shared.account {
            Bugsnag.configuration()?.setUser(account.user_id, withName: account.full_name, andEmail: account.identity_number)
            Crashlytics.sharedInstance().setUserIdentifier(account.user_id)
            Crashlytics.sharedInstance().setUserName(account.full_name)
            Crashlytics.sharedInstance().setUserEmail(account.identity_number)
            Crashlytics.sharedInstance().setObjectValue(Bundle.main.bundleIdentifier ?? "", forKey: "Package")
        }

        CommonUserDefault.shared.checkUpdateOrInstallVersion()
        CommonUserDefault.shared.updateFirstLaunchDateIfNeeded()
    }
    
    private func checkJailbreak() {
        guard UIDevice.isJailbreak else {
            return
        }
        Keychain.shared.clearPIN()
    }
    
    private func initBugsnag() {
        guard let apiKey = MixinKeys.bugsnag else {
            return
        }
        Bugsnag.start(withApiKey: apiKey)
    }
    
    private func checkServerData(isPushKit: Bool = false) {
        guard AccountAPI.shared.didLogin else {
            return
        }
        guard !DatabaseUserDefault.shared.hasUpgradeDatabase() else {
            return
        }
        WebSocketService.shared.checkConnectStatus()

        cancelBackgroundTask()
        self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            self.cancelBackgroundTask()
        })
        let timeInterval: TimeInterval = !isPushKit || BlazeMessageDAO.shared.getCount() + JobDAO.shared.getCount() > 50 ? 120 : 20
        self.backgroundTime = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { (time) in
            self.cancelBackgroundTask()
        }
    }
    
    private func cancelBackgroundTask() {
        self.backgroundTime?.invalidate()
        self.backgroundTime = nil
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    private func updateSharedImageCacheConfig() {
        SDImageCacheConfig.default.maxDiskSize = 1024 * bytesPerMegaByte
        SDImageCacheConfig.default.maxDiskAge = -1
        SDImageCacheConfig.default.diskCacheExpireType = .accessDate
    }
    
    private func dealWithRemoteNotification(_ userInfo: [AnyHashable: Any]?, fromLaunch: Bool = false) {
        guard let userInfo = userInfo, let conversationId = userInfo["conversation_id"] as? String else {
            return
        }
        
        DispatchQueue.global().async {
            guard let conversation = ConversationDAO.shared.getConversation(conversationId: conversationId), conversation.status == ConversationStatus.SUCCESS.rawValue else {
                return
            }
            DispatchQueue.main.async {
                UIApplication.homeNavigationController?.pushViewController(withBackRoot: ConversationViewController.instance(conversation: conversation))
            }
        }
        UNUserNotificationCenter.current().removeAllNotifications()
    }
    
}
