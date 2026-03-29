import UserNotifications
import Foundation

class NotificationService {
    static let shared = NotificationService()

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyTranscriptionComplete(text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Voice note saved"
        content.body = String(text.prefix(200))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
