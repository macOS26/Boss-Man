// Symbolic constants for the wasm port. Keeps tile/font/action keys in one
// place so the maze parser, scene scripts, and SKAction call sites all share
// the same vocabulary. The macOS-only menu / KeyEquivalent / System bits from
// the original aren't included — wasm has no NSApp, no menubar, no /dev/null.
enum Strings {
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
        static let waterGun    = "G"
        static let waterPellet = "A"

        static let floorChar       = Character(floor)
        static let dotChar         = Character(dot)
        static let wallChar        = Character(wall)
        static let hideoutChar     = Character(hideout)
        static let printerChar     = Character(printer)
        static let faxChar         = Character(fax)
        static let coverSheetChar  = Character(coverSheet)
        static let bookBinderChar  = Character(bookBinder)
        static let brownBoxChar    = Character(brownBox)
        static let goldDiscChar    = Character(goldDisc)
        static let workerChar      = Character(worker)
        static let boss1Char       = Character(boss1)
        static let boss2Char       = Character(boss2)
        static let boss3Char       = Character(boss3)
        static let boss4Char       = Character(boss4)
        static let waterGunChar    = Character(waterGun)
        static let waterPelletChar = Character(waterPellet)
    }

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

    // MARK: - In-game messages (transient HUD banners). Ported verbatim
    // from bossman-apple's Strings.Message so the wasm port displays the
    // same wording on every event.
    enum Message {
        static let intro              = "Collect office dots and finish the TPS report!"
        static let practiceMode       = "PRACTICE MODE — score not saved"
        static let paused             = "Paused — press P to resume"
        static let needTPSReport      = "Turn in at least 1 TPS report to complete the level!"
        static let brownBoxHint       = "Brown boxes collect finished TPS reports."
        static let tpsReportReady     = "TPS report complete! Deliver it to a brown box."
        static let newGame            = "New game! Collect dots and TPS reports."
        static let goldDiscActivated  = "Gold disc! Capture the bosses for 20 seconds."
        static let goldDiscEnded      = "Gold disc mode ended."
        static let waterGunActivated  = "Water gun! Shoot the bosses."
        static let waterGunEnded      = "Water gun empty."
        static let waterGunExpired    = "Water gun time expired."
        static let waterGunBlueMode   = "Water pistol unavailable in blue boss mode."
        static let bossSplashed       = "SPLASH!"

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
        static func tpsMissingItems(_ items: [String]) -> String {
            let names = items.map { Machine.displayName[$0] ?? $0 }
            return "The TPS report is missing \(names.joined(separator: ", "))."
        }
        static func tpsTurnedIn(points: Int, gainedLife: Bool) -> String {
            gainedLife
                ? "TPS report turned in! +\(points), extra worker hired."
                : "TPS report turned in! +\(points), workers at max."
        }
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

    // MARK: - Voice lines (spoken through tts_speak)
    enum Speech {
        static let bossCaptureLines = ["Aw, geez.", "Hey now.", "Whoaaa.", "Ouch."]
        static let caughtLines = [
            "TPS reports.", "Cover sheet please.", "Saturday's the day.",
            "Memo, anyone?", "Did you see my shiny red stapler?",
        ]
        static let fishLines = ["Terrific.", "Fantastic.", "Swell.", "Niiice."]
        static let tpsLines  = ["Atta boy.", "Well done.", "Excellent.", "Solid work."]
        static let gameOverLines = [
            "Please clear out your desk.",
            "Security, escort him.",
            "If you would work Saturday, that'd be great.",
            "Did you see my shiny red stapler?",
            "Please add a cover sheet for your TPS Report.",
        ]
        static let levelStartLines = ["Hi there.", "What's happening?", "New floor.", "Welcome back."]
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

    // MARK: - TPS report machines. The name strings double as the keys
    // RoundState.reportItems tracks, matching bossman-apple's Strings.Machine.
    enum Machine {
        static let printer    = "TPS Printer"
        static let fax        = "TPS Fax Machine"
        static let coverSheet = "TPS Cover Sheet"
        static let bookBinder = "TPS Book Binder"
        static let brownBox   = "TPS Delivery Box"
        static let required: [String] = [printer, fax, coverSheet, bookBinder]
        static let displayName: [String: String] = [
            printer:    "Printer",
            fax:        "Fax",
            coverSheet: "Cover Sheet",
            bookBinder: "Book Binder",
        ]
    }

    // MARK: - Emoji glyphs used as SKLabelNode text.
    enum Emoji {
        static let sunglasses = "\u{1F576}\u{FE0F}"           // 🕶
        static let waterGun   = "\u{1F52B}"                    // 🔫
        static let printer    = "\u{1F5A8}\u{FE0F}"           // 🖨
        static let fax        = "\u{1F4E0}"                    // 📠
        static let coverSheet = "\u{1F4C4}"                    // 📄
        static let bookBinder = "\u{1F4DA}"                    // 📚
        static let brownBox   = "\u{1F4E6}"                    // 📦
        static let checked    = "\u{2705}"                     // ✅
        static let unchecked  = "\u{274C}"                     // ❌
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

    enum Worker {
        static let pete = "PETE"
    }

    enum Boss {
        static let bill = "BILL"
        static let dom  = "DOM"
        static let bob  = "BOB"
        static let stan = "STAN"
    }
}
