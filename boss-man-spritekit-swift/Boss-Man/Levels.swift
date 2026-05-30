import Foundation

struct Levels {
    static let levelNames: [String] = (1...24).map { "Level \($0)" }
}

let officeMaps: [[String]] = loadOfficeMapsFromBundle()

private func loadOfficeMapsFromBundle() -> [[String]] {
    guard let url = Bundle.main.url(forResource: Strings.Resource.levelsFile,
                                     withExtension: Strings.Resource.levelsExtension),
          let data = try? Data(contentsOf: url),
          let dict = try? JSONDecoder().decode([String: [String]].self, from: data)
    else {
        return Array(repeating: emptyLevelRows(), count: Levels.levelNames.count)
    }
    return Levels.levelNames.map { dict[$0] ?? emptyLevelRows() }
}

private func emptyLevelRows() -> [String] {
    var rows: [String] = []
    let topBottom = String(repeating: "#", count: 18) + " " + String(repeating: "#", count: 17)
    rows.append(topBottom)
    for r in 1...15 {
        let leftEdge: Character = (r == 8) ? " " : "#"
        let rightEdge: Character = (r == 8) ? " " : "#"
        rows.append(String(leftEdge) + String(repeating: ".", count: 34) + String(rightEdge))
    }
    rows.append(topBottom)
    return rows
}
