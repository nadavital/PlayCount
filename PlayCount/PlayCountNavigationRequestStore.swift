import Foundation

enum PlayCountNavigationRequestStore {
    private static let latestRecapKey = "PlayCount.PendingLatestRecapNavigation"
    private static let recapMonthKey = "PlayCount.PendingRecapMonth"

    static func requestLatestRecap(monthStart: Date? = nil) {
        UserDefaults.standard.set(true, forKey: latestRecapKey)
        if let monthStart {
            UserDefaults.standard.set(monthStart.timeIntervalSinceReferenceDate, forKey: recapMonthKey)
        } else {
            UserDefaults.standard.removeObject(forKey: recapMonthKey)
        }
    }

    static func consumeLatestRecapRequest() -> Bool {
        guard UserDefaults.standard.bool(forKey: latestRecapKey) else { return false }
        UserDefaults.standard.removeObject(forKey: latestRecapKey)
        return true
    }

    static func consumeRequestedRecapMonth() -> Date? {
        guard UserDefaults.standard.object(forKey: recapMonthKey) != nil else { return nil }
        let interval = UserDefaults.standard.double(forKey: recapMonthKey)
        UserDefaults.standard.removeObject(forKey: recapMonthKey)
        return Date(timeIntervalSinceReferenceDate: interval)
    }
}
