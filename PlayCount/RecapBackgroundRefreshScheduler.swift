import BackgroundTasks
import Foundation

enum RecapBackgroundRefreshScheduler {
    static let identifier = "com.nadavavital.PlayCount.recap-refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("Failed to schedule recap background refresh: \(error)")
            #endif
        }
    }
}
