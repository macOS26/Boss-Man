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

    // MARK: - Machines / TPS report items
    enum Machine {
        static let printer    = "TPS Printer"
        static let fax        = "TPS Fax Machine"
        static let coverSheet = "TPS Cover Sheet"
        static let bookBinder = "TPS Book Binder"
        static let brownBox   = "TPS Delivery Box"

        static let required: [String] = [printer, fax, coverSheet, bookBinder]

        static let displayNames: [String: String] = [
            printer:    "Printer",
            fax:        "Fax",
            coverSheet: "Cover Sheet",
            bookBinder: "Book Binder"
        ]
    }

    // MARK: - In-game messages (transient HUD banners)
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
            let names = items.map { Machine.displayNames[$0] ?? $0 }
            return "The TPS report is missing \(names.joined(separator: ", "))."
        }

        static func tpsTurnedIn(points: Int, gainedLife: Bool) -> String {
            gainedLife
                ? "TPS report turned in! +\(points), extra worker hired."
                : "TPS report turned in! +\(points), workers at max."
        }
    }
}
