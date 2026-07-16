import Foundation

/// One thing wrong with the evolution graph.
///
/// These are all SEMANTIC errors — a graph has to decode before it can be validated. A syntax or
/// unknown-enum error never reaches this type: `EvolutionGraph.bundled` traps at launch, and under
/// `xcodebuild test` the app is the TEST_HOST, so the runner dies before a single test reports.
/// See the note on `EvolutionGraph.bundled` for how to read that failure.
enum GraphValidationError: Error, Equatable, CustomStringConvertible {
    /// An edge names a node that does not exist — the line dead-ends into nothing.
    case unknownEdgeTarget(from: String, to: String)

    /// A node's `spriteFile` resolves to no file on disk, so it would render as a placeholder.
    case missingSprite(node: String, path: String)

    /// A node's `spriteFile` is empty. Called out separately because it is not merely absent art:
    /// `Bundle.url(forResource:)` treats an empty name like nil and hands back an ARBITRARY png
    /// from the directory, so this is how a node silently becomes the wrong Digimon (see
    /// `SpriteLoader.url`, which guards it). Reported here rather than left to a nil load, since a
    /// caller that does not guard would "find" art and pass.
    case emptySpriteFile(node: String)

    /// An edge that does not advance exactly one rung of the Digitama -> Ultimate ladder.
    /// Stages off the ladder (Armor-Hybrid, whose `ladderIndex` is nil) are not checked.
    case invalidStageTransition(from: String, to: String, fromStage: Stage, toStage: Stage)

    /// A non-terminal node with no fallback edge. US-020 takes the `isDefault` edge once the time
    /// gate passes and nothing else qualifies; without one the Digimon is permanently stuck.
    case noDefaultEdge(node: String)

    /// More than one fallback on a node — US-020's choice would come down to edge order.
    case multipleDefaultEdges(node: String, count: Int)

    /// Two nodes share an id. `EvolutionGraph.byId` silently keeps the first, so the second is
    /// unreachable: every edge pointing at that id resolves to the wrong Digimon.
    case duplicateId(String, count: Int)

    /// An edge names one of the 157 idle-only Digimon. They have no animated sheet, so making one
    /// playable means slicing 12 frames out of a lone 16x16 sprite.
    case edgeToDexOnlyNode(from: String, to: String)

    /// An edge out of a hatched node with no `requiredEnergy`. Only a Digitama's hatch edge may
    /// omit it (US-018 hatches on TOTAL energy, so no single type gates it); anywhere else the
    /// edge has no dominant-type gate and US-019 cannot decide a branch.
    case missingRequiredEnergy(from: String, to: String)

    /// A Digitama edge that names a `requiredEnergy`. It would be data that lies: US-018 ignores
    /// it, and a later reader would eventually "fix" the engine to respect it and break hatching.
    case typeGatedHatch(from: String, to: String, energy: EnergyType)

    var description: String {
        switch self {
        case let .unknownEdgeTarget(from, to):
            return "\(from) -> \(to): no node has id '\(to)'"
        case let .missingSprite(node, path):
            return "\(node): spriteFile does not exist on disk (\(path))"
        case let .emptySpriteFile(node):
            return "\(node): spriteFile is empty — it would load an arbitrary sprite"
        case let .invalidStageTransition(from, to, fromStage, toStage):
            return "\(from) -> \(to): \(fromStage.rawValue) to \(toStage.rawValue) does not advance exactly one stage"
        case let .noDefaultEdge(node):
            return "\(node): non-terminal node has no isDefault edge — it can get stuck"
        case let .multipleDefaultEdges(node, count):
            return "\(node): \(count) isDefault edges — the fallback is ambiguous"
        case let .duplicateId(id, count):
            return "'\(id)' is declared \(count) times — all but the first are unreachable"
        case let .edgeToDexOnlyNode(from, to):
            return "\(from) -> \(to): '\(to)' is dexOnly and has no animated sheet"
        case let .missingRequiredEnergy(from, to):
            return "\(from) -> \(to): no requiredEnergy, but only a Digitama's hatch edge may omit it"
        case let .typeGatedHatch(from, to, energy):
            return "\(from) -> \(to): a hatch must not be gated on \(energy.rawValue) — US-018 hatches on total energy"
        }
    }
}

extension EvolutionGraph {
    /// Answers "does this node's art exist?".
    ///
    /// Injectable because the check is the one part of validation that touches the world: a model
    /// fixture has no art on disk, and a test for the OTHER rules must not fail on that.
    typealias SpriteExistsCheck = (EvolutionNode) -> Bool

    /// Resolves art the way the app does — under the stage folder, or the flat `Idle Frame Only`
    /// folder for a dexOnly node, whose art is not filed by stage.
    static func spriteExists(in bundle: Bundle = .main) -> SpriteExistsCheck {
        { node in
            let folder = node.dexOnly ? SpriteLoader.idleFrameOnlyFolder : node.stage.rawValue
            return SpriteLoader.url(stage: folder, name: node.spriteFile, in: bundle) != nil
        }
    }

    /// Every error in the graph, in node order. Empty means the graph is sound.
    ///
    /// Returns ALL errors rather than throwing on the first: fixing a roster one error per test
    /// run is miserable, and the errors are independent.
    func validate(spriteExists: SpriteExistsCheck = EvolutionGraph.spriteExists()) -> [GraphValidationError] {
        var errors: [GraphValidationError] = []

        // Duplicates are found against `nodes` (the file as authored), not `byId`, which keeps
        // only the first of a pair and so cannot see them.
        let countsById = Dictionary(nodes.map { ($0.id, 1) }, uniquingKeysWith: +)
        for id in countsById.keys.sorted() where countsById[id]! > 1 {
            errors.append(.duplicateId(id, count: countsById[id]!))
        }

        for node in nodes {
            errors.append(contentsOf: validate(node: node, spriteExists: spriteExists))
        }
        return errors
    }

    private func validate(node: EvolutionNode, spriteExists: SpriteExistsCheck) -> [GraphValidationError] {
        var errors: [GraphValidationError] = []

        if node.spriteFile.isEmpty {
            errors.append(.emptySpriteFile(node: node.id))
        } else if !spriteExists(node) {
            let folder = node.dexOnly ? SpriteLoader.idleFrameOnlyFolder : node.stage.rawValue
            errors.append(.missingSprite(node: node.id, path: "\(folder)/\(node.spriteFile).png"))
        }

        if !node.evolutions.isEmpty {
            let defaults = node.evolutions.filter(\.isDefault).count
            if defaults == 0 {
                errors.append(.noDefaultEdge(node: node.id))
            } else if defaults > 1 {
                errors.append(.multipleDefaultEdges(node: node.id, count: defaults))
            }
        }

        for edge in node.evolutions {
            errors.append(contentsOf: validate(edge: edge, from: node))
        }
        return errors
    }

    private func validate(edge: EvolutionEdge, from node: EvolutionNode) -> [GraphValidationError] {
        var errors: [GraphValidationError] = []

        switch (node.stage, edge.requiredEnergy) {
        case (.digitama, .some(let energy)):
            errors.append(.typeGatedHatch(from: node.id, to: edge.to, energy: energy))
        case (_, .none) where node.stage != .digitama:
            errors.append(.missingRequiredEnergy(from: node.id, to: edge.to))
        default:
            break
        }

        guard let target = self.node(id: edge.to) else {
            // Everything below reads the target, so there is nothing further to say about it.
            return errors + [.unknownEdgeTarget(from: node.id, to: edge.to)]
        }

        if target.dexOnly {
            errors.append(.edgeToDexOnlyNode(from: node.id, to: edge.to))
        }

        // A nil ladderIndex means "off the ladder" (Armor-Hybrid), which is unknown rather than
        // wrong — treating it as a rung would make every edge touching it a false error.
        if let from = node.stage.ladderIndex, let to = target.stage.ladderIndex, to != from + 1 {
            errors.append(.invalidStageTransition(
                from: node.id, to: edge.to, fromStage: node.stage, toStage: target.stage))
        }
        return errors
    }
}
