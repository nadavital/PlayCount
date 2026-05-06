import Foundation
import UserNotifications

extension Notification.Name {
    static let openMonthlyRecap = Notification.Name("PlayCountOpenMonthlyRecap")
}

final class RecapNotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RecapNotificationScheduler()

    private enum Identifier {
        static let weekly = "playcount.weekly-recap"
        static let monthly = "playcount.monthly-recap"
        static let debug = "playcount.debug-recap"
    }

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationAndSchedule() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                scheduleDefaultRecapNotifications()
            }
            return granted
        } catch {
            return false
        }
    }

    func scheduleDefaultRecapNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.weekly, Identifier.monthly])
        center.add(weeklyRequest())
        center.add(monthlyRequest())
    }

    #if DEBUG
    func scheduleDebugRecapNotification() {
        let content = recapContent(
            title: "Check your PlayCount recap",
            body: "Open PlayCount to refresh your latest listening snapshot."
        )
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.debug, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    #endif

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.userInfo["destination"] as? String == "recap" else {
            return
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .openMonthlyRecap, object: nil)
        }
    }

    private func weeklyRequest() -> UNNotificationRequest {
        var date = DateComponents()
        date.weekday = 2
        date.hour = 9
        date.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let content = recapContent(
            title: "Your weekly PlayCount recap is ready",
            body: "Open PlayCount to refresh your latest snapshot and see what changed."
        )
        return UNNotificationRequest(identifier: Identifier.weekly, content: content, trigger: trigger)
    }

    private func monthlyRequest() -> UNNotificationRequest {
        var date = DateComponents()
        date.day = 1
        date.hour = 9
        date.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let content = recapContent(
            title: "Your monthly PlayCount recap is ready",
            body: "Open PlayCount to capture the latest counters and review your month."
        )
        return UNNotificationRequest(identifier: Identifier.monthly, content: content, trigger: trigger)
    }

    private func recapContent(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["destination": "recap"]
        return content
    }
}
