import Foundation

// Constants shared verbatim across apple + wasm, extracted from each port's
// Strings.swift so the level grammar, emoji glyphs, and character names live in
// one place. Platform-specific Strings enums (fonts, DefaultsKey, Title, Editor,
// Speech voice infra, menus) stay in each port's own Strings.swift.
extension Strings {
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

        static let floorChar         = Character(floor)
        static let dotChar           = Character(dot)
        static let wallChar          = Character(wall)
        static let hideoutChar       = Character(hideout)
        static let printerChar       = Character(printer)
        static let faxChar           = Character(fax)
        static let coverSheetChar    = Character(coverSheet)
        static let bookBinderChar    = Character(bookBinder)
        static let brownBoxChar      = Character(brownBox)
        static let goldDiscChar      = Character(goldDisc)
        static let workerChar        = Character(worker)
        static let boss1Char         = Character(boss1)
        static let boss2Char         = Character(boss2)
        static let boss3Char         = Character(boss3)
        static let boss4Char         = Character(boss4)
        static let waterGunChar      = Character(waterGun)
        static let waterPelletChar   = Character(waterPellet)
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
        static let waterGun   = "🔫"
    }

    // MARK: - Worker (PETE) names
    enum Worker {
        static let pete = "PETE"
        static let hero = "HERO"
    }

    // MARK: - Boss display names
    enum Boss {
        static let bill = "BILL"
        static let dom  = "DOM"
        static let bob  = "BOB"
        static let stan = "STAN"
        static let boss = "BOSS"
    }
}
