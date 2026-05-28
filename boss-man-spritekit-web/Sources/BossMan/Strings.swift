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
        static let pressSpace = "P to Play \u{00B7} E for Editor"
        static let controlsHint = "Cursor key to Move \u{00B7} Space to Fire Water Pistol"
        static func highScore(_ value: Int) -> String { "HIGH SCORE \(value)" }
    }

    // MARK: - localStorage keys for persistent state (mirror UserDefaults
    // keys from the original; the kit's store_get/store_set bridges them).
    enum DefaultsKey {
        static let highScore              = "BossMan.highScore"
        static let leaderboard            = "BossMan.leaderboard"
        static let playerName             = "BossMan.playerName"
        static let localLeaderboardUsername = "BossMan.username"
        static let startFullscreen        = "BossMan.startFullscreen"
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
    }
}
