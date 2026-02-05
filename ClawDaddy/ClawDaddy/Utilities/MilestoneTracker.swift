import Foundation

struct MilestoneReward {
    let message: String
    let emote: EmoteStyle?
    let dance: Bool
    let salute: Bool
}

struct MilestoneTracker {
    var commandCount: Int
    var streakDays: Int

    private static let streakMilestones: [Int: String] = [
        3: "Three days at sea, cap'n. Getting our sea legs.",
        7: "A full week on the water! Ye be a true sailor.",
        14: "Two weeks! The crew's never been sharper.",
        30: "A month! The crew salutes ye, cap'n.",
    ]

    private static let commandMilestones: [Int: (String, EmoteStyle?)] = [
        10: ("Tenth order, cap'n! The crew remembers every one.", nil),
        50: ("Fifty orders! This ship runs like clockwork.", nil),
        100: ("A hundred orders! Ye run a tight ship.", .backflip),
        500: ("Five hundred! Cap'n of the century.", .spin),
        1000: ("A THOUSAND. Captain legend.", .backflip),
    ]

    mutating func trackCommand() -> MilestoneReward? {
        commandCount += 1
        UserDefaults.standard.set(commandCount, forKey: "clawdaddy.commandCount")
        guard let (message, emote) = Self.commandMilestones[commandCount] else { return nil }
        let achieved = UserDefaults.standard.stringArray(forKey: "clawdaddy.commandMilestones") ?? []
        let key = String(commandCount)
        guard !achieved.contains(key) else { return nil }
        UserDefaults.standard.set(achieved + [key], forKey: "clawdaddy.commandMilestones")
        return MilestoneReward(message: message, emote: emote, dance: true, salute: false)
    }

    mutating func updateStreak() -> MilestoneReward? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let key = "clawdaddy.lastOpenDate"
        let streakKey = "clawdaddy.streakDays"

        if let lastDate = UserDefaults.standard.object(forKey: key) as? Date {
            let lastDay = calendar.startOfDay(for: lastDate)
            let diff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if diff == 1 {
                streakDays = UserDefaults.standard.integer(forKey: streakKey) + 1
            } else if diff == 0 {
                streakDays = max(1, UserDefaults.standard.integer(forKey: streakKey))
            } else {
                streakDays = 1
            }
        } else {
            streakDays = 1
        }
        UserDefaults.standard.set(today, forKey: key)
        UserDefaults.standard.set(streakDays, forKey: streakKey)

        guard let message = Self.streakMilestones[streakDays] else { return nil }
        let achieved = UserDefaults.standard.stringArray(forKey: "clawdaddy.streakMilestones") ?? []
        let milestoneKey = String(streakDays)
        guard !achieved.contains(milestoneKey) else { return nil }
        UserDefaults.standard.set(achieved + [milestoneKey], forKey: "clawdaddy.streakMilestones")
        return MilestoneReward(message: message, emote: nil, dance: streakDays >= 30, salute: streakDays >= 30)
    }
}
