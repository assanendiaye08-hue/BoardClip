import AppKit
import Observation

/// A durable, named board that clips can be saved into permanently (beyond the rolling history).
struct Space: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = "tray.full"   // SF Symbol
    var colorHex: String = "#0A84FF"
    var sortIndex: Int = 0
    var createdAt: Date = Date()
}

@MainActor
@Observable
final class SpaceStore {
    private(set) var spaces: [Space] = []

    func load() {
        guard let data = try? Data(contentsOf: AppPaths.spacesFile),
              let decoded = try? JSONDecoder.iso.decode([Space].self, from: data) else { return }
        spaces = decoded.sorted { $0.sortIndex < $1.sortIndex }
    }

    private func save() {
        guard let data = try? JSONEncoder.iso.encode(spaces) else { return }
        try? data.write(to: AppPaths.spacesFile, options: .atomic)
    }

    @discardableResult
    func add(name: String, symbol: String = "tray.full", colorHex: String = "#0A84FF") -> Space {
        let space = Space(name: name, symbol: symbol, colorHex: colorHex, sortIndex: spaces.count)
        spaces.append(space)
        save()
        return space
    }

    func rename(_ space: Space, to name: String) {
        guard let i = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        spaces[i].name = name
        save()
    }

    func update(_ space: Space) {
        guard let i = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        spaces[i] = space
        save()
    }

    func delete(_ space: Space, from history: HistoryStore) {
        spaces.removeAll { $0.id == space.id }
        history.removeSpaceReference(space.id)
        save()
    }

    func space(for id: UUID) -> Space? { spaces.first { $0.id == id } }
}
