import Foundation

enum Strings {
    static let empty = String()

    // MARK: - Level char tokens (the level-file grammar)
    enum Tile {
        static let floor      = " "
        static let dot        = "."
        static let wall       = "#"
        static let hideout    = "H"
        static let printer    = "P"
        static let fax        = "F"
        static let coverSheet = "C"
        static let bookBinder = "M"
        static let brownBox   = "D"
        static let goldDisc   = "O"
        static let worker     = "W"
        static let boss1      = "1"
        static let boss2      = "2"
        static let boss3      = "3"
        static let boss4      = "4"

        static let floorChar      = Character(floor)
        static let dotChar        = Character(dot)
        static let wallChar       = Character(wall)
        static let hideoutChar    = Character(hideout)
        static let printerChar    = Character(printer)
        static let faxChar        = Character(fax)
        static let coverSheetChar = Character(coverSheet)
        static let bookBinderChar = Character(bookBinder)
        static let brownBoxChar   = Character(brownBox)
        static let goldDiscChar   = Character(goldDisc)
        static let workerChar     = Character(worker)
        static let boss1Char      = Character(boss1)
        static let boss2Char      = Character(boss2)
        static let boss3Char      = Character(boss3)
        static let boss4Char      = Character(boss4)
    }

    // MARK: - macOS standard menu item titles
    enum Menu {
        static let hideOthers = "Hide Others"
        static let showAll    = "Show All"
        static let view       = "View"
        static let window     = "Window"
        static let minimize   = "Minimize"
        static let close      = "Close"
        static func about(_ appName: String) -> String { "About \(appName)" }
        static func hide(_  appName: String) -> String { "Hide \(appName)" }
        static func quit(_  appName: String) -> String { "Quit \(appName)" }
    }

    // MARK: - macOS key equivalents (single-letter shortcuts in main menu)
    enum KeyEquivalent {
        static let none       = Strings.empty
        static let hide       = "h"
        static let fullscreen = "f"
        static let minimize   = "m"
        static let close      = "w"
        static let quit       = "q"
        static let save       = "s"
        static let undo       = "z"
        static let undoShift  = "Z"
        static let play       = "p"
        static let reveal     = "r"
    }

    // MARK: - Plain keyboard chars (event.characters values)
    enum Key {
        static let digit0 = "0"
        static let digit1 = Tile.boss1
        static let digit2 = Tile.boss2
        static let digit3 = Tile.boss3
        static let digit4 = Tile.boss4
        static let digit5 = "5"
        static let digit6 = "6"
        static let digit7 = "7"
        static let digit8 = "8"
    }

    // MARK: - System / engineering constants
    enum System {
        static let osActivityModeKey = "OS_ACTIVITY_MODE"
        static let osActivityDisable = "disable"
        static let devNull           = "/dev/null"
        static let writeMode         = KeyEquivalent.close
        static let initCoderUnsupported = "init(coder:) is not supported"
    }

    // MARK: - Font names (PostScript IDs passed to SKLabelNode / NSFont)
    enum Font {
        static let menloBold       = "Menlo-Bold"
        static let menlo           = "Menlo"
        static let helveticaBold   = "Helvetica-Bold"
        static let markerFeltThin  = "Marker Felt Thin"
        static let markerFeltWide  = "Marker Felt Wide"
    }

    // MARK: - SKAction keys (the per-scope "name" passed to run(_:withKey:))
    enum ActionKey {
        static let walk             = "walk"
        static let spawnShield      = "spawnShield"
        static let spawnShieldBlink = "spawnShieldBlink"
        static let machineCooldown  = "machineCooldown"
        static let goldDiscExpiry   = "goldDiscExpiry"
        static let bossMove         = "bossMove"
        static let workerMove       = "workerMove"
        static let bossStepper      = "bossStepper"
        static let travelerStepper  = "travelerStepper"
        static let travelerVisit1   = "travelerVisit1"
        static let travelerVisit2   = "travelerVisit2"
        static let spawnFade        = "spawnFade"
        static let spawnUnfreeze    = "spawnUnfreeze"
        static let spawnThrob       = "spawnThrob"
        static let clear            = "clear"
    }

    // MARK: - SKNode names (used by hit-testing / find-by-name)
    enum NodeName {
        static let signInLink     = "leaderboard.signin_link"
        static let palettePrefix  = "pal_"
        static let travelerEmoji  = "traveler.emoji"
    }

    // MARK: - Bundle resources (filename + extension passed to Bundle.url)
    enum Resource {
        static let levelsFile        = "levels"
        static let levelsExtension   = "json"
        static let levelsJSON        = "levels.json"
        static let emptyJSON         = "{}"
        static let redStaplerFile    = "red-stapler"
        static let redStaplerExtension = "png"
        // Level-6 traveler-only PNG (separate asset from the title-screen PNG).
        // This asset faces RIGHT by default — see LevelTraveler.facesRight.
        static let travelerStaplerFile      = "shinyredstapler-emoji"
        static let travelerStaplerExtension = "png"
        static let quarantineAttribute = "com.apple.quarantine"
    }

    // MARK: - Machine icons (emoji)
    enum Emoji {
        static let printer    = "🖨️"
        static let fax        = "📠"
        static let coverSheet = "📄"
        static let bookBinder = "📚"
        static let brownBox   = "📦"
        static let checked    = "✅"
        static let unchecked  = "❌"
        static let sunglasses = "🕶️"
    }

    // MARK: - Level Editor copy / labels
    enum Editor {
        static let title         = "LEVEL EDITOR"
        // Labels are padded so the suffix column (arrows / parenthesised
        // shortcuts) lines up in the editor's monospaced font.
        static let prev          = "PREV  <"
        static let next          = "NEXT  >"
        static let undo          = "UNDO  command Z"
        static let redo          = "REDO  shift command Z"
        static let clear         = "CLEAR command delete"
        static let clearConfirmTitle       = "Clear this level?"
        static let clearConfirmBody        = "This wipes every tile to floor. You can undo immediately with ⌘Z."
        static let clearConfirmDestructive = "Clear"
        static let clearConfirmCancel      = "Cancel"
        static let save          = "SAVE  command S"
        static let revealFile    = "SHOW  command R"
        static let play          = "PLAY  command P"
        static let back          = "BACK  ESC"
        static let nothingUndo   = "Nothing to undo"
        static let nothingRedo   = "Nothing to redo"
        static let undoToast     = "Undo"
        static let redoToast     = "Redo"
        static let savedToast    = "SAVED!"
        static func tilePrefix(_ name: String) -> String { "Tile: \(name)" }
        static func levelCounter(_ current: Int, of total: Int) -> String { "(\(current)/\(total))" }
        static func tileNodeName(row: Int, col: Int) -> String { "tile_\(row)_\(col)" }
        static let tileWallInitial = "Tile: Wall"
        static let nameDashSeparator = " - "
        enum Tile {
            static let floor    = "Floor"
            static let dot      = "Dot"
            static let wall     = "Wall"
            static let hideout  = "Hideout"
            static let goldDisc = "Gold Disc"
        }
    }

    // MARK: - Leaderboard panel
    enum Leaderboard {
        static let header = "LEADERBOARD"
        static func rankLabel(_ rank: Int) -> String { "\(rank)." }
        static func scoreLabel(_ score: Int) -> String { "\(score)" }
        static let newHighScoreTitle = "NEW HIGH SCORE!"
        static let enterUsernamePrompt = "Enter your username:"
        static let usernamePlaceholder = "Player"
        static let saveButton = "Save"
        static let skipButton = "Skip"
    }

    // MARK: - Score popup
    enum Score {
        static func popup(_ points: Int) -> String { points >= 0 ? "+\(points)" : "\(points)" }
    }

    // MARK: - CoreImage / system framework constants
    enum CoreImage {
        static let gaussianBlur      = "CIGaussianBlur"
        static let inputRadiusKey    = "inputRadius"
    }

    // MARK: - Editor button identifiers (used as SKNode.name + click dispatch)
    enum EditorButton {
        static let prev      = "btn_prev"
        static let next      = "btn_next"
        static let undo      = "btn_undo"
        static let redo      = "btn_redo"
        static let clear     = "btn_clear"
        static let save      = "btn_save"
        static let reveal    = "btn_reveal"
        static let play      = "btn_play"
        static let back      = "btn_back"
    }

    // MARK: - Player / system fallbacks
    enum Player {
        static let unknownTag = "Player"
    }

    // MARK: - UserDefaults keys
    enum DefaultsKey {
        static let highScore        = "Boss-Man.highScore"
        static let startFullscreen  = "Boss-Man.startFullscreen"
        static let localHighScores  = "Boss-Man.localHighScores"
        static let localLeaderboardUsername = "Boss-Man.localLeaderboardUsername"
    }

    // MARK: - Game Center
    enum GameCenter {
        static let leaderboardID = "BossManLeaderBoard0001"
    }

    // MARK: - Speech / voice
    enum Speech {
        static let fallback = "Yeah."
        static let usEnglish = "en-US"
        static let englishPrefix = "en"
        static let roboticVoiceNames = [
            "fred", "ralph", "bahh", "bells", "boing", "bubbles",
            "cellos", "deranged", "good news", "hysterical",
            "pipe organ", "trinoids", "whisper", "zarvox"
        ]
        static let preferredMaleVoiceNames = [
            "reed", "rocco", "tom", "aaron", "alex", "evan", "daniel"
        ]
        static let caughtFallback   = "Ohh, yeah."
        static let fishFallback     = "Mmm, yeah."
        static let tpsFallback      = "Sounds great."
        static let gameOverFallback = "yeah right!"

        static let bossCaptureLines = [
            "Aw, geez.",
            "Hey now.",
            "Whoaaa.",
            "Ouch."
        ]
        static let caughtLines = [
            "TPS reports.",
            "Cover sheet please.",
            "Saturday's the day.",
            "Memo, anyone?",
            "Did you see my shiny red stapler?"
        ]
        static let fishLines = [
            "Terrific.",
            "Fantastic.",
            "Swell.",
            "Niiice."
        ]
        static let tpsLines = [
            "Atta boy.",
            "Well done.",
            "Excellent.",
            "Solid work."
        ]
        static let gameOverLines = [
            "Please clear out your desk.",
            "Security, escort him.",
            "If you would work Saturday, that'd be great.",
            "Did you see my shiny red stapler?",
            "Please add a cover sheet for your TPS Report."
        ]
        static let levelStartLines = [
            "Hi there.",
            "What's happening?",
            "New floor.",
            "Welcome back."
        ]
    }

    // MARK: - Sound buffer cache keys (passed to SoundManager.cached(_:))
    enum SoundCache {
        static let goldDisc      = "goldDisc"
        static let footstep      = "footstep"
        static let caughtByBoss  = "caughtByBoss"
        static let fishOrTreat   = "fishOrTreat"
        static let tpsDeliver    = "tpsDeliver"
        static let gameOver      = "gameOver"
        static let levelStart    = "levelStart"
        static let teleport      = "teleport"
        static let printer       = "printer"
        static let fax           = "fax"
        static let pageFlip      = "pageFlip"
        static let collator      = "collator"
        static let captureBossPrefix = "captureBoss-"
        static let travelerPrefix = "trav."
        static func dotKey(stage: Int, highToggle: Bool, mib: Bool) -> String {
            "dot-\(stage)-\(highToggle ? "hi" : "lo")\(mib ? "-mib" : "")"
        }
    }

    // MARK: - Machines / TPS report items
    enum Machine {
        static let printer    = "TPS Printer"
        static let fax        = "TPS Fax Machine"
        static let coverSheet = "TPS Cover Sheet"
        static let bookBinder = "TPS Book Binder"
        static let brownBox   = "TPS Delivery Box"

        static let required: [String] = [printer, fax, coverSheet, bookBinder]
    }

    // MARK: - Worker (PETE) names
    enum Worker {
        static let pete = "PETE"
    }

    // MARK: - Boss display names
    enum Boss {
        static let boss     = "BILL"
        static let lumbergh = "DOM"
        static let waddams  = "BOB"
        static let bolton   = "STAN"
    }

    // MARK: - HUD persistent labels
    enum HUD {
        static let livesPrefix     = "Lives:"
        static let tpsPrefix       = "TPS:"
        static let empty           = Strings.empty
        static let tpsItemSeparator   = "  "
        static let emojiTrailSeparator = Tile.floor

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
        static let bundleName             = "Boss-Man"
        static var applicationSupportRelativePath: String {
            "Library/Application Support/\(bundleName)"
        }
        static func gameCenterAuthFailed(_ description: String) -> String {
            "Game Center auth failed: \(description)"
        }
        static let startFullscreen        = "Start in Full Screen"
        static let enterFullscreen        = "Enter Full Screen"
        static let exitFullscreen         = "Exit Full Screen"
        static let resetLocalLeaderboard  = "Reset Local Leaderboard…"
        static let resetAlertTitle        = "Reset Local Leaderboard?"
        static let resetAlertBody         = "This clears every high-score entry stored on this Mac. Game Center scores are unaffected and can only be reset from App Store Connect."
        static let resetButton            = "Reset"
        static let cancelButton           = "Cancel"
        static let gameCenter             = "Game Center"
        static let signInToGameCenter     = "Sign in to Game Center"
        static let loading                = "Loading…"
    }
}
