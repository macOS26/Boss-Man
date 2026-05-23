//
//  Strings.swift
//  Boss-Man
//
//  Single source of truth for user-facing copy. Anything the player can
//  read on screen (HUD messages, title labels, menu items, machine /
//  boss display names, prompts) lives here so renames, tone tweaks, or
//  a future localization pass touch one file.
//
//  Convention:
//    – Plain `static let` for constant strings.
//    – `static func` for templates that interpolate variables.
//    – Internal-only debug logs / cache keys stay in their source file;
//      this file is for COPY, not engineering strings.
//

import Foundation

enum Strings {

    // MARK: - Machines / TPS report items
    enum Machine {
        static let printer    = "Printer"
        static let fax        = "Fax"
        static let coverSheet = "Cover Sheet"
        static let bookBinder = "Book Binder"
        static let brownBox   = "Brown TPS Box"

        /// Required-item list passed to GameScene and HUD.
        static let required: [String] = [printer, fax, coverSheet, bookBinder]
    }

    // MARK: - Boss display names
    enum Boss {
        static let boss     = "BOSS"
        static let lumbergh = "LUMBERGH"
        static let waddams  = "WADDAMS"
        static let bolton   = "BOLTON"
    }

    // MARK: - HUD persistent labels
    enum HUD {
        static let livesPrefix = "Lives:"
        static let tpsPrefix   = "TPS:"

        /// `Score: N   High: N   Level: N   Dots: D/T   Reports: R`
        static func statusLine(score: Int, highScore: Int, level: Int,
                               dots: Int, total: Int, reports: Int) -> String {
            "Score: \(score)   High: \(highScore)   Level: \(level)   Dots: \(dots)/\(total)   Reports: \(reports)"
        }

        static let gameOver         = "GAME OVER"
        static let promptNewGame    = "PRESS SPACE TO START A NEW GAME"
        static let promptTitle      = "PRESS ESC FOR TITLE SCREEN"
    }

    // MARK: - In-game messages (transient HUD banners)
    enum Message {
        static let intro              = "Collect office dots and finish the TPS report!"
        static let practiceMode       = "PRACTICE MODE — score not saved"
        static let paused             = "Paused — press SPACE to resume"
        static let needTPSReport      = "Turn in at least 1 TPS report to complete the level!"
        static let brownBoxHint       = "Brown boxes collect finished TPS reports."
        static let tpsReportReady     = "TPS report complete! Deliver it to a brown box."
        static let newGame            = "New game! Collect dots and TPS reports."
        static let goldDiscActivated  = "Gold disc! Capture the bosses for 20 seconds."
        static let goldDiscEnded      = "Gold disc mode ended."

        static func bossCaughtYou(_ livesLeft: Int) -> String {
            "A boss caught you! \(livesLeft) workers left."
        }

        static func levelLoaded(_ level: Int) -> String {
            "Level \(level)! New office floor loaded."
        }

        static func bossCaptured(name: String, points: Int) -> String {
            "\(name) captured! +\(points)"
        }

        static func travelerCaught(emoji: String, points: Int) -> String {
            "Caught \(emoji)! +\(points)"
        }

        static func reportItemCollected(name: String, points: Int) -> String {
            "Collected \(name) page for TPS report +\(points)"
        }

        static func tpsTurnedIn(points: Int, gainedLife: Bool) -> String {
            gainedLife
                ? "TPS report turned in! +\(points), extra worker hired."
                : "TPS report turned in! +\(points), workers at max."
        }
    }

    // MARK: - Title scene
    enum Title {
        static let gameTitle      = "BOSS-MAN"
        static let pressSpace     = "SPACE to Play · E for Editor"
        static func highScore(_ value: Int) -> String { "HIGH SCORE \(value)" }
    }

    // MARK: - App menu / system dialogs
    enum App {
        static let startFullscreen        = "Start in Full Screen"
        static let resetLocalLeaderboard  = "Reset Local Leaderboard…"
        static let resetAlertTitle        = "Reset Local Leaderboard?"
        static let resetAlertBody         = "This clears every high-score entry stored on this Mac. Game Center scores are unaffected and can only be reset from App Store Connect."
        static let resetButton            = "Reset"
        static let cancelButton           = "Cancel"
        static let gameCenter             = "Game Center"
        static let signInToGameCenter     = "Sign in to Game Center"
    }
}
