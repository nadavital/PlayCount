import Foundation
import UserNotifications

extension Notification.Name {
    static let openMonthlyRecap = Notification.Name("PlayCountOpenMonthlyRecap")
}

final class RecapNotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RecapNotificationScheduler()

    private enum Identifier {
        static let weekly = "playcount.weekly-recap"
        static let backgroundUpdate = "playcount.background-update"
        static let monthly = "playcount.monthly-recap"
        static let debug = "playcount.debug-recap"
    }

    private enum DefaultsKey {
        static let lastBackgroundUpdateWeek = "playcount.last-background-update-week"
        static let lastMilestoneID = "playcount.last-notified-milestone"
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

    func scheduleBackgroundUpdate(_ update: BackgroundRecapUpdate) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let defaults = UserDefaults.standard

        let content: UNMutableNotificationContent
        if let milestone = update.newlyEarnedMilestone {
            let milestoneKey = "\(Calendar.current.component(.year, from: Date()))-\(milestone.id)"
            guard defaults.string(forKey: DefaultsKey.lastMilestoneID) != milestoneKey else { return }
            content = recapContent(
                title: "New PlayCount medal",
                body: milestone.achievementDescription
            )
            defaults.set(milestoneKey, forKey: DefaultsKey.lastMilestoneID)
        } else {
            let calendar = Calendar.current
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
            let weekKey = weekStart.timeIntervalSinceReferenceDate
            guard defaults.double(forKey: DefaultsKey.lastBackgroundUpdateWeek) != weekKey else { return }
            let insight = update.weeklyComparison.current
            guard insight.hasActivity else { return }
            if let song = insight.topSong {
                content = recapContent(
                    title: "\(song.title) led your week",
                    body: "\(song.playDelta.formatted()) plays so far. See the rest of your weekly listening in PlayCount."
                )
            } else {
                content = recapContent(
                    title: "Your week in music is ready",
                    body: "You listened for \(insight.totalListeningDuration.formattedListeningMinutes). See what changed in PlayCount."
                )
            }
            defaults.set(weekKey, forKey: DefaultsKey.lastBackgroundUpdateWeek)
        }

        center.removePendingNotificationRequests(withIdentifiers: [Identifier.weekly, Identifier.backgroundUpdate])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5 * 60, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Identifier.backgroundUpdate, content: content, trigger: trigger))
        try? await center.add(weeklyRequest())
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
            title: "Your week in music is ready",
            body: "Open PlayCount to see your latest listening highlights."
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
            body: "See the music, movement, and medals that shaped your month."
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
