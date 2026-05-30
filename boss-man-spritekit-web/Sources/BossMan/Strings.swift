// Symbolic constants for the wasm port. Keeps tile/font/action keys in one
// place so the maze parser, scene scripts, and SKAction call sites all share
// the same vocabulary. The macOS-only menu / KeyEquivalent / System bits from
// the original aren't included — wasm has no NSApp, no menubar, no /dev/null.
enum Strings {
    // MARK: - Font names. The runtime's font preloader registers each .ttf
    // by its filename basename (e.g. MarkerFelt-Wide.ttf → "MarkerFelt-Wide").
    // SKLabelNode.fontName feeds those exact strings to font_by_name; on the
    // macOS build the same constants resolve to the PostScript IDs of system
    // fonts because Apple ships Marker Felt under both spellings.
    enum Font {
        static let menloBold      = "Menlo-Bold"
        static let menlo          = "Menlo"
        static let helveticaBold  = "Helvetica-Bold"
        static let markerFeltThin = "MarkerFelt-Thin"
        static let markerFeltWide = "MarkerFelt-Wide"
        static let jetBrainsMono  = "JetBrainsMono-Bold"
    }

    // MARK: - Title screen copy
    enum Title {
        static let gameTitle = "BOSS-MAN"
        static let playGame    = "(P)lay"
        static let levelEditor = "(E)ditor"
        static let controlsHint = "Cursor key to Move \u{00B7} Space to Fire Water Pistol"
        static func highScore(_ value: Int) -> String { "HIGH SCORE \(value)" }
    }

    // MARK: - localStorage keys for persistent state (mirror UserDefaults
    // keys from the original; the kit's store_get/store_set bridges them).
    enum DefaultsKey {
        static let highScore              = "BossMan.highScore"
        static let leaderboard            = "BossMan.leaderboard"
        static let localHighScores        = "BossMan.leaderboard"   // shared LocalHighScores key (same store as `leaderboard`)
        static let playerName             = "BossMan.playerName"
        static let localLeaderboardUsername = "BossMan.username"
        static let startFullscreen        = "BossMan.startFullscreen"
        static let bossTracksSquare       = "BossMan.bossTracksSquare"
        static let waterGunLeft           = "BossMan.waterGunLeft"
        static let editorLastLevelIndex   = "BossMan.editorLastLevelIndex"
        static let editorLevelPrefix      = "BossMan.editorLevel."
    }

    // MARK: - CoreImage / system framework constants
    enum CoreImage {
        static let gaussianBlur   = "CIGaussianBlur"
        static let inputRadiusKey = "inputRadius"
    }

    enum App {
        static let loading = "Loading…"
    }

    enum GameCenter {
        static let leaderboardID = "BossManLeaderBoard0001"
    }

    enum System {
        static let initCoderUnsupported = "init(coder:) is not supported"
    }

    enum Score {
        static func popup(_ points: Int) -> String { points >= 0 ? "+\(points)" : "\(points)" }
    }

    enum Resource {
        static let travelerStaplerFile = "shinyredstapler-emoji-160x244"
    }

    // MARK: - HUD persistent label prefixes (mirrors Strings.HUD in apple)
    enum HUDText {
        static let livesPrefix    = "Lives:"
        static let tpsPrefix      = "TPS:"
        static let gameOver       = "GAME OVER"
        static let promptNewGame  = "PRESS P TO START A NEW GAME"
        static let promptTitle    = "PRESS ESC FOR TITLE SCREEN"
        static func statusLine(score: Int, highScore: Int, level: Int,
                               dots: Int, total: Int, reports: Int) -> String {
            "Score: \(score)   High: \(highScore)   Level: \(level)   Dots: \(dots)/\(total)   Reports: \(reports)"
        }
    }


    // MARK: - Leaderboard / username dialog strings
    enum Leaderboard {
        static let header              = "LEADERBOARD"
        static let newHighScoreTitle   = "NEW HIGH SCORE!"
        static let enterUsernamePrompt = "Enter your username:"
        static let usernamePlaceholder = "Player"
        static let saveButton          = "Save  (Enter)"
        static let skipButton          = "Skip  (Esc)"
        static let noScores            = "No local scores yet."
        static func rankLabel(_ rank: Int) -> String { "\(rank)." }
        static func scoreLabel(_ score: Int) -> String { "\(score)" }
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
        static let spawnFade        = "spawnFade"
        static let spawnUnfreeze    = "spawnUnfreeze"
        static let blink            = "blink"
        static let travelerVisit1   = "travelerVisit1"
        static let travelerVisit2   = "travelerVisit2"
    }

    enum NodeName {
        static let travelerEmoji = "traveler.emoji"
        static let palettePrefix = "pal_"
        static let signInLink    = "leaderboard.signin_link"
    }

    // MARK: - Level editor copy. Button-label key hints describe the WEB
    // shortcuts (bare letters / arrows) since the wasm runtime can't deliver
    // the macOS Command-modifier combos the original used.
    enum Editor {
        static let title         = "LEVEL EDITOR"
        static let prev          = "PREV  <"
        static let next          = "NEXT  >"
        static let undo          = "UNDO  Z"
        static let redo          = "REDO  Y"
        static let clear         = "CLEAR del"
        static let reset         = "RESET R"
        static let save          = "SAVE  S"
        static let revealFile    = "SHOW"
        static let copy          = "COPY  C"
        static let paste         = "PASTE V"
        static let play          = "PLAY  P"
        static let back          = "BACK  ESC"
        static let copyToast     = "Copied"
        static let pasteToast    = "Pasted"
        static let nothingPaste  = "Nothing to paste"
        static let nothingUndo   = "Nothing to undo"
        static let nothingRedo   = "Nothing to redo"
        static let undoToast     = "Undo"
        static let redoToast     = "Redo"
        static let savedToast    = "SAVED!"
        static let clearedToast  = "Cleared (Z to undo)"
        static let resetToast    = "Reset to built-in (Z to undo)"
        static let revealToast   = "Saved to browser storage"
        static let autosaveToast = "AUTOSAVE 1 min"
        static let tileWallInitial = "Tile: Wall"
        static func tilePrefix(_ name: String) -> String { "Tile: \(name)" }
        static func levelCounter(_ current: Int, of total: Int) -> String { "(\(current)/\(total))" }
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

    enum EditorButton {
        static let prev   = "btn_prev"
        static let next   = "btn_next"
        static let undo   = "btn_undo"
        static let redo   = "btn_redo"
        static let clear  = "btn_clear"
        static let reset  = "btn_reset"
        static let save   = "btn_save"
        static let reveal = "btn_reveal"
        static let copy   = "btn_copy"
        static let paste  = "btn_paste"
        static let play   = "btn_play"
        static let back   = "btn_back"
    }

}
