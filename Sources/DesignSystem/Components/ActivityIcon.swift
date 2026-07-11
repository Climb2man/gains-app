import SwiftUI

enum ActivityIcon {
    static let map: [String: String] = [
        "running": "figure.run", "walking": "figure.walk", "hiking": "figure.hiking",
        "cycling": "figure.outdoor.cycle", "hand-cycling": "figure.outdoor.cycle",
        "swimming": "figure.pool.swim", "rowing": "figure.rower", "sailing": "sailboat.fill",
        "strength-training": "figure.strengthtraining.traditional",
        "core-training": "figure.core.training", "cross-training": "figure.cross.training",
        "hiit": "figure.highintensity.intervaltraining", "flexibility": "figure.flexibility",
        "stretching": "figure.flexibility", "cooldown": "figure.cooldown",
        "mind-body": "figure.mind.and.body", "pilates": "figure.pilates", "dancing": "figure.dance",
        "dance-inspired-training": "figure.dance", "yoga": "figure.yoga", "boxing": "figure.boxing",
        "kickboxing": "figure.kickboxing", "martial-arts": "figure.martial.arts",
        "elliptical": "figure.elliptical", "stair-climbing": "figure.stair.stepper",
        "step-training": "figure.step.training", "jump-rope": "figure.jumprope",
        "basketball": "figure.basketball", "american-football": "figure.american.football",
        "australian-football": "figure.australian.football", "soccer": "figure.soccer",
        "baseball": "figure.baseball", "softball": "figure.softball", "cricket": "figure.cricket",
        "golf": "figure.golf", "tennis": "figure.tennis", "badminton": "figure.badminton",
        "pickleball": "figure.pickleball", "racquetball": "figure.racquetball",
        "squash": "figure.squash", "handball": "figure.handball", "bowling": "figure.bowling",
        "hockey": "figure.hockey", "lacrosse": "figure.lacrosse", "rugby": "figure.rugby",
        "climbing": "figure.climbing", "archery": "figure.archery", "fencing": "figure.fencing",
        "gymnastics": "figure.gymnastics", "curling": "figure.curling", "fishing": "figure.fishing",
        "hunting": "figure.hunting", "equestrian-sports": "figure.equestrian.sports",
        "skating-sports": "figure.skating", "snow-sports": "figure.snowboarding",
        "downhill-skiing": "figure.skiing.downhill", "cross-country-skiing": "figure.skiing.crosscountry",
        "paddle-sports": "figure.outdoor.rowing", "disc-sports": "figure.disc.sports",
        "fitness-gaming": "gamecontroller.fill", "play": "figure.play",
        "mixed-cardio": "figure.mixed.cardio", "mixed-metabolic-cardio-training": "figure.mixed.cardio",
        "other": "figure.run",
    ]

    static func symbol(for activity: String) -> String {
        let key = activity
            .replacingOccurrences(of: "activity-icon/activity-", with: "")
            .replacingOccurrences(of: "activity-", with: "")
        return map[key] ?? "figure.mixed.cardio"
    }
}
