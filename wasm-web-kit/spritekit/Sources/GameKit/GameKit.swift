import SpriteKit
import UIKit
import KitABI

// =============================================================================
// GameKit shim — Game Center is unavailable on the open web, so these classes
// behave as a silent local stub: posting scores succeeds; leaderboard queries
// return empty; authentication completes with no player. Games keep their
// Game Center call sites intact and can still ship a local high-score table
// (Space-Bar uses GKLocalPlayer.displayName for the player name).
// =============================================================================

public final class GKLocalPlayer {
    public static let local = GKLocalPlayer()
    public var isAuthenticated = false
    public var displayName = "Player"
    public var alias = "Player"
    public var playerID = "local"
    public var authenticateHandler: ((UIViewController?, Error?) -> Void)? {
        didSet { authenticateHandler?(nil, nil) }    // immediately resolve as unauthenticated
    }
    public func loadFriendsAuthorizationStatus(_ h: @escaping (GKFriendsAuthorizationStatus, Error?) -> Void) {
        h(.notDetermined, nil)
    }
    public func loadFriends(_ h: @escaping ([GKPlayer]?, Error?) -> Void) { h([], nil) }
}

public enum GKFriendsAuthorizationStatus: Int { case notDetermined, restricted, denied, authorized }

public final class GKPlayer {
    public var displayName = ""
    public var playerID = ""
}

// =============================================================================
public final class GKScore {
    public var leaderboardIdentifier: String?
    public var value: Int64 = 0
    public var context: UInt64 = 0
    public var player: GKPlayer?
    public init() {}
    public init(leaderboardIdentifier id: String) { self.leaderboardIdentifier = id }
    public static func report(_ scores: [GKScore], withCompletionHandler h: @escaping (Error?) -> Void) { h(nil) }
}

// =============================================================================
public final class GKLeaderboard {
    public enum PlayerScope: Int { case global, friendsOnly }
    public enum TimeScope: Int { case today, week, allTime }
    public final class Entry {
        public var player = GKPlayer()
        public var rank = 0
        public var score = 0
        public var formattedScore = ""
        public init() {}
    }
    public var identifier: String?
    public var playerScope: PlayerScope = .global
    public var timeScope: TimeScope = .allTime
    public var range = (1, 10)
    public init() {}
    public init(players: [GKPlayer]) {}
    public func loadScores(completionHandler h: @escaping ([GKScore]?, Error?) -> Void) { h([], nil) }
    public static func loadLeaderboards(IDs: [String]?, completionHandler h: @escaping ([GKLeaderboard]?, Error?) -> Void) { h([], nil) }
    public static func loadLeaderboards(IDs: [String]?) async throws -> [GKLeaderboard] { [] }
    public func loadEntries(for players: [GKPlayer], timeScope: TimeScope,
                            completionHandler h: @escaping (GKLeaderboardEntry?, [GKLeaderboardEntry]?, Error?) -> Void) {
        h(nil, [], nil)
    }
    public func loadEntries(for playerScope: PlayerScope, timeScope: TimeScope,
                            range: NSRange) async throws -> (Entry?, [Entry], Int) {
        (nil, [], 0)
    }
}

public struct NSRange {
    public var location: Int
    public var length: Int
    public init(location: Int, length: Int) { self.location = location; self.length = length }
}

// NSCoder drives NSCoding archiving on Apple; the web port never archives, so
// this name-only stub lets shared `required init?(coder: NSCoder)` signatures
// compile. Those inits all trap with fatalError and are never reached.
public final class NSCoder {
    public init() {}
}

public final class GKLeaderboardEntry {
    public var player: GKPlayer?
    public var score: Int = 0
    public var rank: Int = 0
    public var formattedScore: String = ""
}

// =============================================================================
public final class GKAchievement {
    public var identifier: String?
    public var percentComplete: Double = 0
    public var isCompleted: Bool { percentComplete >= 100 }
    public var showsCompletionBanner = false
    public init() {}
    public init(identifier id: String) { self.identifier = id }
    public static func report(_ achievements: [GKAchievement], withCompletionHandler h: @escaping (Error?) -> Void) { h(nil) }
    public static func loadAchievements(completionHandler h: @escaping ([GKAchievement]?, Error?) -> Void) { h([], nil) }
    public static func resetAchievements(completionHandler h: @escaping (Error?) -> Void) { h(nil) }
}

// =============================================================================
public final class GKAccessPoint {
    public static let shared = GKAccessPoint()
    public var isActive = false
    public var location = 0
    public var showHighlights = false
    public func trigger(handler h: @escaping () -> Void) { h() }
}

// =============================================================================
// GKGameCenterViewController — opens the Game Center UI on iOS/macOS. On web
// it's a compile-only stub; the delegate's didFinish is called immediately.
public protocol GKGameCenterControllerDelegate: AnyObject {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController)
}
public final class GKGameCenterViewController: UIViewController {
    public enum State: Int { case `default`, leaderboards, achievements, challenges, localPlayerProfile }
    public weak var gameCenterDelegate: GKGameCenterControllerDelegate?
    public var viewState: State = .default
    public override init() { super.init() }
    public init(state: State) { super.init(); self.viewState = state }
    public func present(from vc: UIViewController) { gameCenterDelegate?.gameCenterViewControllerDidFinish(self) }
}

// GK callbacks all use Swift.Error — comes from the stdlib, no redeclaration needed.
