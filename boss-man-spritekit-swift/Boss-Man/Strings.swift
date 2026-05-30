import Foundation

enum Strings {
    static let empty = String()

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
        static let copy       = "c"
        static let paste      = "v"
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

    // MARK: - Bundle resources (filename + extension passed to Bundle.url)
    enum Resource {
        static let levelsFile        = "levels"
        static let levelsExtension   = "json"
        static let levelsJSON        = "levels.json"
        static let emptyJSON         = "{}"
        static let redStaplerFile    = "red-stapler"
        static let redStaplerExtension = "png"
        static let travelerStaplerFile      = "shinyredstapler-emoji"
        static let travelerStaplerExtension = "png"
        static let quarantineAttribute = "com.apple.quarantine"
    }

    // MARK: - Level Editor copy / labels
    enum Editor {
        static let title         = "LEVEL EDITOR"
        static let prev          = "PREV  <"
        static let next          = "NEXT  >"
        static let undo          = "UNDO  Z"
        static let redo          = "REDO  Y"
        static let reset         = "RESET R"
        static let clear         = "CLEAR del"
        static let clearConfirmTitle       = "Clear this level?"
        static let clearConfirmBody        = "This wipes every tile to floor. You can undo immediately with Z."
        static let clearConfirmDestructive = "Clear"
        static let clearConfirmCancel      = "Cancel"
        static let save          = "SAVE  S"
        static let revealFile    = "SHOW"
        static let copy          = "COPY  C"
        static let paste         = "PASTE V"
        static let play          = "PLAY  P"
        static let back          = "BACK  ESC"
        static let resetToast    = "Reset to built-in (Z to undo)"
        static let copyToast     = "Copied"
        static let pasteToast    = "Pasted"
        static let nothingPaste  = "Nothing to paste"
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
            static let floor       = "Floor"
            static let dot         = "Dot"
            static let wall        = "Wall"
            static let hideout     = "Hideout"
            static let goldDisc    = "Gold Disc"
            static let waterGun    = "Water Gun"
            static let waterPellet = "Water Pellets"
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
        static let noScores = "No local scores yet."
    }

    // MARK: - Editor button identifiers (used as SKNode.name + click dispatch)
    enum EditorButton {
        static let prev      = "btn_prev"
        static let next      = "btn_next"
        static let undo      = "btn_undo"
        static let redo      = "btn_redo"
        static let clear     = "btn_clear"
        static let reset     = "btn_reset"
        static let save      = "btn_save"
        static let reveal    = "btn_reveal"
        static let copy      = "btn_copy"
        static let paste     = "btn_paste"
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
        static let bossTracksSquare = "Boss-Man.bossTracksSquare"
        static let waterGunLeft     = "Boss-Man.waterGunLeft"
    }

    // MARK: - Game Center
    enum GameCenter {
        static let leaderboardID = "BossManLeaderBoard0001"
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
        static let waterGunPickup = "waterGunPickup"
        static let waterGunShoot  = "waterGunShoot"
        static let waterGunSplash = "waterGunSplash"
        static func dotKey(stage: Int, highToggle: Bool, mib: Bool) -> String {
            "dot-\(stage)-\(highToggle ? "hi" : "lo")\(mib ? "-mib" : "")"
        }
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
        static let promptNewGame    = "PRESS P TO START A NEW GAME"
        static let promptTitle      = "PRESS ESC FOR TITLE SCREEN"
    }

    // MARK: - Title scene
    enum Title {
        static let gameTitle      = "BOSS-MAN"
        static let pressSpace     = "P to Play · E for Editor"
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

// macOS-only NSSpeechSynthesizer voice-picker infra; the shared spoken-line
// pools live in Strings+Shared. Web has no synthesizer voice selection.
extension Strings.Speech {
    static let fallback = "Yeah."
    static let usEnglish = "en-US"
    static let englishPrefix = "en"
    static let roboticVoiceNames = [
        "bahh", "bells", "boing", "bubbles",
        "cellos", "deranged", "good news", "hysterical",
        "pipe organ", "trinoids", "whisper", "zarvox", "albert", "eddy"
    ]
    static let preferredVoiceNames = [
        "rocko", "ralph", "fred", "reed", "grandpa", "junior",
        "daniel"
    ]
    static let caughtFallback   = "Ohh, yeah."
    static let fishFallback     = "Mmm, yeah."
    static let tpsFallback      = "Sounds great."
    static let gameOverFallback = "yeah right!"
}
