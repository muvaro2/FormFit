import Foundation

struct AppUserProfile: Identifiable {
    let name: String
    let memberSince: String
    let weeklyBestScore: Int?
    let isCurrentUser: Bool

    var id: String {
        isCurrentUser ? "current-user" : name
    }
}

enum AppUserDirectory {
    static let currentUserName = "FormFit Athlete"
    static let currentUserMemberSince = "Apr 2026"

    static let friendProfiles: [AppUserProfile] = [
        AppUserProfile(name: "Maya Chen", memberSince: "Feb 2024", weeklyBestScore: 96, isCurrentUser: false),
        AppUserProfile(name: "Jordan Lee", memberSince: "Mar 2024", weeklyBestScore: 94, isCurrentUser: false),
        AppUserProfile(name: "Ava Patel", memberSince: "Jan 2024", weeklyBestScore: 91, isCurrentUser: false),
        AppUserProfile(name: "Chris Park", memberSince: "Apr 2024", weeklyBestScore: 89, isCurrentUser: false)
    ]

    static func currentUserProfile(weeklyBestScore: Int?) -> AppUserProfile {
        AppUserProfile(
            name: currentUserName,
            memberSince: currentUserMemberSince,
            weeklyBestScore: weeklyBestScore,
            isCurrentUser: true
        )
    }
}
