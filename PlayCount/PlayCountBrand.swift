import SwiftUI
import UIKit

enum PlayCountBrand {
    static let burgundy = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            UIColor(red: 0.76, green: 0.08, blue: 0.29, alpha: 1)
        } else {
            UIColor(red: 0.62, green: 0.04, blue: 0.23, alpha: 1)
        }
    })

    static let gold = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            UIColor(red: 1.00, green: 0.72, blue: 0.16, alpha: 1)
        } else {
            UIColor(red: 0.67, green: 0.40, blue: 0.02, alpha: 1)
        }
    })

    static var accent: Color {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-PlayCountAccentGold") {
            return gold
        }
        if arguments.contains("-PlayCountAccentBurgundy") {
            return burgundy
        }
        #endif

        return burgundy
    }
}
