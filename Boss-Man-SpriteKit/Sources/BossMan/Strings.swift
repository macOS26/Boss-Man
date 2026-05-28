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

    // MARK: - Font names (PostScript IDs passed to SKLabelNode). On wasm
    // these resolve through the kit's font preloader (manifest.json) — fall
    // back to a default if the family isn't present.
    enum Font {
        static let menloBold      = "Menlo-Bold"
        static let menlo          = "Menlo"
        static let helveticaBold  = "Helvetica-Bold"
        static let markerFeltThin = "Marker Felt Thin"
        static let markerFeltWide = "Marker Felt Wide"
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
        static let highScore        = "BossMan.highScore"
        static let leaderboard      = "BossMan.leaderboard"
        static let playerName       = "BossMan.playerName"
        static let startFullscreen  = "BossMan.startFullscreen"
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
    }
}
