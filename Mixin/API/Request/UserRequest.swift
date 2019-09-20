import Foundation

struct UserPreferenceRequest: Codable {
    let full_name: String?
    let avatar_base64: String?
    let notification_token: String?
    let receive_message_source: String?
    let accept_conversation_source: String?
}

extension UserPreferenceRequest {

    static func createRequest(full_name: String? = nil, avatar_base64: String? = nil, notification_token: String? = nil, receive_message_source: String? = nil, accept_conversation_source: String? = nil) -> UserPreferenceRequest {
        return UserPreferenceRequest(full_name: full_name, avatar_base64: avatar_base64, notification_token: notification_token, receive_message_source: receive_message_source, accept_conversation_source: accept_conversation_source)
    }

}
