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

        static let floorChar         = Array(floor.utf8)[0]
        static let dotChar           = Array(dot.utf8)[0]
        static let wallChar          = Array(wall.utf8)[0]
        static let hideoutChar       = Array(hideout.utf8)[0]
        static let printerChar       = Array(printer.utf8)[0]
        static let faxChar           = Array(fax.utf8)[0]
        static let coverSheetChar    = Array(coverSheet.utf8)[0]
        static let bookBinderChar    = Array(bookBinder.utf8)[0]
        static let brownBoxChar      = Array(brownBox.utf8)[0]
        static let goldDiscChar      = Array(goldDisc.utf8)[0]
        static let workerChar        = Array(worker.utf8)[0]
        static let boss1Char         = Array(boss1.utf8)[0]
        static let boss2Char         = Array(boss2.utf8)[0]
        static let boss3Char         = Array(boss3.utf8)[0]
        static let boss4Char         = Array(boss4.utf8)[0]
        static let waterGunChar      = Array(waterGun.utf8)[0]
        static let waterPelletChar   = Array(waterPellet.utf8)[0]
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
        static let milt  = "MILT"
        static let bobs  = "BOBS"
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
        static let intro              = "Collect dots and the TPS report!"
        static let practiceMode       = "Practice mode (no score)"
        static let paused             = "Paused (P to resume)"
        static let needTPSReport      = "Turn in 1 TPS report first!"
        static let brownBoxHint       = "Brown boxes take TPS reports"
        static let tpsReportReady     = "TPS ready! Drop at a brown box"
        static let newGame            = "New game!"
        static let goldDiscActivated  = "Gold disc! Catch the bosses"
        static let goldDiscEnded      = "Gold disc over"
        static let waterGunActivated  = "Water gun! Soak the bosses"
        static let waterGunEnded      = "Out of water"
        static let waterGunExpired    = "Water gun expired"
        static let waterGunBlueMode   = "No water gun in blue mode"
        static let bossSplashed       = "SPLASH!"

        static func bossCaughtYou(_ livesLeft: Int) -> String {
            "Boss got you! \(livesLeft) left"
        }

        static func levelLoaded(_ level: Int) -> String {
            "Level \(level)!"
        }

        static func bossCaptured(name: String, points _: Int) -> String {
            "\(name) captured!"
        }

        static func travelerCaught(emoji: String, points _: Int) -> String {
            "Caught \(emoji)!"
        }

        static func reportItemCollected(name: String, points _: Int) -> String {
            "Got \(name)"
        }

        static func tpsMissingItems(_ items: [String]) -> String {
            let names = items.map { Machine.displayNames[$0] ?? $0 }
            return "Missing: \(names.joined(separator: ", "))"
        }

        static func tpsTurnedIn(points _: Int, gainedLife: Bool) -> String {
            gainedLife ? "TPS in! New worker hired" : "TPS turned in!"
        }
    }

    // MARK: - Speech / voice lines (the spoken-line pools)
    enum Speech {
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

    // MARK: - CoreImage / system framework constants
    enum CoreImage {
        static let gaussianBlur   = "CIGaussianBlur"
        static let inputRadiusKey = "inputRadius"
    }

    // MARK: - Score popup
    enum Score {
        static func popup(_ points: Int) -> String { points >= 0 ? "+\(points)" : "\(points)" }
    }

    // MARK: - SKNode names (hit-testing / find-by-name)
    enum NodeName {
        static let signInLink     = "leaderboard.signin_link"
        static let palettePrefix  = "pal_"
        static let travelerEmoji  = "traveler.emoji"
        static let waterPellet    = "waterPellet"
    }

    // MARK: - SKAction keys (union of both ports, unused keys are harmless)
    enum ActionKey {
        static let walk             = "walk"
        static let spawnShield      = "spawnShield"
        static let spawnShieldBlink = "spawnShieldBlink"
        static let machineCooldown  = "machineCooldown"
        static let goldDiscExpiry   = "goldDiscExpiry"
        static let workerMove       = "workerMove"
        static let travelerStepper  = "travelerStepper"
        static let travelerVisit1   = "travelerVisit1"
        static let travelerVisit2   = "travelerVisit2"
        static let spawnFade        = "spawnFade"
        static let spawnUnfreeze    = "spawnUnfreeze"
        static let blink            = "blink"
        static let spawnThrob       = "spawnThrob"
        static let fleeThaw         = "fleeThaw"
        static let waterGunExpiry   = "waterGunExpiry"
        static let clear            = "clear"
        static let hudSwap          = "hudSwap"
    }
}

// MARK: - JSON string escaping (shared by LocalHighScores and LevelEditorScene)

func jsonEscape(_ s: String) -> String {
    var out = ""
    for ch in s {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:   out.append(ch)
        }
    }
    return out
}

func jsonReadString(_ a: [Character], _ n: Int, _ start: Int) -> (String, Int) {
    var i = start + 1, s = ""
    while i < n, a[i] != "\"" {
        if a[i] == "\\", i + 1 < n {
            switch a[i + 1] {
            case "n": s.append("\n")
            case "t": s.append("\t")
            case "r": s.append("\r")
            default:  s.append(a[i + 1])
            }
            i += 2
        } else {
            s.append(a[i])
            i += 1
        }
    }
    return (s, min(i + 1, n))
}
