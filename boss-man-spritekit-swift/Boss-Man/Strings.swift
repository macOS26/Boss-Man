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

    // MARK: - Font names. PostScript names resolve the same face on both: the
    // wasm preloader registers each .ttf by its basename, and CoreText accepts
    // the PostScript name on macOS.
    enum Font {
        static let menloBold       = "Menlo-Bold"
        static let menlo           = "Menlo"
        static let helveticaBold   = "Helvetica-Bold"
        static let jetBrainsMono   = "JetBrainsMono-Bold"
        static let markerFeltThin  = "MarkerFelt-Thin"
        static let markerFeltWide  = "MarkerFelt-Wide"
    }

    // MARK: - Bundle resources (filename + extension passed to Bundle.url on
    // macOS; the wasm asset preloader registers names directly).
    enum Resource {
        static let levelsFile        = "levels"
        static let levelsExtension   = "json"
        static let levelsJSON        = "levels.json"
        static let emptyJSON         = "{}"
        static let redStaplerFile    = "red-stapler"
        static let redStaplerExtension = "png"
        static let travelerStaplerExtension = "png"
        static let quarantineAttribute = "com.apple.quarantine"
        static let travelerStaplerFile = "shinyredstapler-emoji"
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
        static let resetToast    = "Reset (Z to undo)"
        static let copyToast     = "Copied"
        static let pasteToast    = "Pasted"
        static let nothingPaste  = "Nothing to paste"
        static let nothingUndo   = "Nothing to undo"
        static let nothingRedo   = "Nothing to redo"
        static let undoToast     = "Undo"
        static let redoToast     = "Redo"
        static let savedToast    = "SAVED!"
        static let clearedToast  = "Cleared (Z to undo)"
        static let revealToast   = "Saved to browser storage"
        static let autosaveToast = "AUTOSAVE 1 min"
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
        static let noScores = "No local scores yet."
        static let saveButton = "Save"
        static let skipButton = "Skip"
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

    // MARK: - Persistence keys (UserDefaults on macOS, localStorage on wasm).
    // Shared key strings on both platforms; only the storage backend differs.
    // Changing a key re-keys persisted data.
    enum DefaultsKey {
        static let highScore              = "BossMan.highScore"
        static let leaderboard            = "BossMan.leaderboard"
        static let localHighScores        = "BossMan.leaderboard"
        static let playerName             = "BossMan.playerName"
        static let localLeaderboardUsername = "BossMan.username"
        static let startFullscreen        = "BossMan.startFullscreen"
        static let bossTracksSquare       = "BossMan.bossTracksSquare"
        static let mazeZoom               = "BossMan.mazeZoom"
        static let waterGunLeft           = "BossMan.waterGunLeft"
        static let waterGunHide           = "BossMan.waterGunHide"
        static let editorLastLevelIndex   = "BossMan.editorLastLevelIndex"
        static let editorLevelPrefix      = "BossMan.editorLevel."
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

        static func compactScore(_ score: Int) -> String { "\(score)" }
        static let paused = "PAUSED"
        static let reportBooks = ["📙", "📘", "📗", "📕"]
        static func compactReports(_ reports: Int) -> String {
            let shown = reports <= 0 ? 0 : (reports - 1) % reportBooks.count + 1
            return (0..<shown).map { reportBooks[$0] }.joined()
        }

        static let gameOver         = "GAME OVER"
        static let promptNewGame    = "PRESS P TO START A NEW GAME"
        static let promptTitle      = "PRESS ESC FOR TITLE SCREEN"
    }

    // MARK: - Title scene
    enum Title {
        static let gameTitle      = "BOSS-MAN"
        static let pressSpace     = "P to Play · E for Editor"
        static let playGame       = "PLAY"
        static let levelEditor    = "EDITOR"
        static let controlsHint   = "Cursor key to Move \u{00B7} Space to Fire Water Pistol"
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

// Voice-picker data. apple ranks these in-process (NSSpeechSynthesizer);
// wasm forwards them to the runtime as CSVs (tts_set_*). The shared spoken-line
// pools live in Strings+Shared.
extension Strings.Speech {
    static let fallback = "Yeah."
    static let usEnglish = "en-US"
    static let englishPrefix = "en"
    static let roboticVoiceNames = [
        "bahh", "bells", "boing", "bubbles",
        "cellos", "deranged", "good news", "hysterical",
        "pipe organ", "trinoids", "whisper", "zarvox", "albert", "eddy"
    ]
    // Voice selection mirrors the wasm master (wasm is the source of truth for
    // voice): Ralph leads since Rocko isn't exposed in Safari; Daniel is last.
    static let preferredVoiceNames = [
        "ralph", "rocko", "fred", "alex", "david", "mark",
        "reed", "grandpa", "junior", "google us english", "daniel"
    ]
    // Ranked last on apple; sent to the wasm runtime so it can deprioritize them.
    static let femaleVoiceNames = [
        "samantha", "karen", "tessa", "moira", "ava", "susan", "victoria",
        "allison", "veena", "fiona", "kate", "kathy", "sandy", "whisper",
        "paulina", "monica", "marie", "zira", "hazel", "heather", "jenny",
        "aria", "catherine", "clara", "linda", "sara",
        "google uk english female", "google us english female"
    ]
    static let caughtFallback   = "Ohh, yeah."
    static let fishFallback     = "Mmm, yeah."
    static let tpsFallback      = "Sounds great."
    static let gameOverFallback = "yeah right!"
}

// MARK: - Maze zoom (title-screen camera mode)
enum MazeZoom {
    static let doom = 1993  // sentinel: the single-hit raycaster (RAYCAST 3D)
    static let voxel = 1994 // sentinel: the overhead voxel-span view (VOXEL 3D)
    static let iso = 1995   // sentinel: the isometric block view (ISOMETRIC)
    static let cycle = [1980, 1982, 1983, 1993, 1994, 1995]
    static var current: Int {
        let z = Persistence.int(forKey: Strings.DefaultsKey.mazeZoom)
        return cycle.contains(z) ? z : 1983
    }
    static var isDoom: Bool { current == doom }
    static var isVoxel: Bool { current == voxel }
    static var isIso: Bool { current == iso }
    static var is3D: Bool { isDoom || isVoxel || isIso }   // any full-screen scene mode (vs the 2D follow-camera eras)
    // The 2D follow-camera zoom for each era (100 = no camera). Ms. Pac-Man = 150%,
    // Jr. Pac-Man = 200%; Pac-Man is classic 100%, DOOM uses the 3D path instead.
    static var zoomPercent: Int {
        switch current {
        case 1982: return 150
        case 1983: return 200
        default:   return 100
        }
    }
    static var label: String {
        switch current {
        case 1980: return "FULL 2D"
        case 1982: return "ZOOM 2D"
        case 1983: return "MACRO 2D"
        case 1993: return "RAYCAST 3D"
        case 1994: return "VOXEL 3D"
        case 1995: return "ISOMETRIC 3D"
        default:   return "\(current)"
        }
    }
    static func advance() {
        let i = cycle.firstIndex(of: current) ?? 0
        Persistence.set(cycle[(i + 1) % cycle.count], forKey: Strings.DefaultsKey.mazeZoom)
    }
}
