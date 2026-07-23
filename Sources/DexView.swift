import SwiftUI

/// The field guide: every Digimon in the roster, with the ones you have raised filled in.
///
/// The top level is ONE flat grid over all 1,022 roster entries (US-063), not the list of evolution
/// lines it was through US-042. The list only ever showed the ~88 Digimon an authored line reaches,
/// so the other ~930 that have art on disk were invisible — and "how much of the roster have I
/// met?" is the question the Dex exists to answer, which a list of eight line names cannot.
///
/// What made the list affordable was that its rows were text. The grid gets there a different way:
/// `LazyVGrid` builds only the cells on screen, and a cell is the only thing that reaches
/// `IdleSpriteCache`, so scrolling past 1,022 entries decodes the dozen or so actually visible.
/// Opening the Dex still decodes nothing at all.
///
/// The trees have not gone away, and US-067 did not retire them: `model.sections` still holds them
/// and `DexDetailView` now links through to the one that owns the Digimon you opened. The grid
/// answers "what have I met", which a list of eight line names cannot; the tree answers "what shape
/// is this line", which a flat grid cannot. The way in is the grid; the tree is one tap deeper.
struct DexView: View {
    @StateObject private var model: DexModel

    #if DEBUG
    @State private var showsLineDemo = CommandLine.arguments.contains("-dexLineDemo")
        || CommandLine.arguments.contains { $0.hasPrefix("-dexLineDemo=") }
    #endif

    /// As in `ContentView`: passed in rather than defaulted, because building one is a
    /// `@MainActor` call and a default argument would run in this non-isolated `init`.
    init(model: @autoclosure @escaping () -> DexModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        DexGridView(rows: model.rows, selectsDemoRow: true, context: model.conditionContext,
                    sections: model.sections)
            .navigationTitle("\(model.discoveredCount)/\(model.totalCount)")
            #if DEBUG
            // Debug-only: `simctl` cannot tap a cell, so an opened line is unscreenshottable
            // without a way to push one from the launch command — the same reason `-dexDemo` exists
            // to push this screen at all. Compiled out of release builds.
            .navigationDestination(isPresented: $showsLineDemo) {
                if let section = demoSection { destination(for: section) }
            }
            #endif
            .onAppear {
                if !model.isLoaded { model.load() }
            }
            // US-179: reads today's health metrics off the wrist and re-resolves the hint context, so
            // the detail sheet can answer a standing measurement a running total cannot hold. Off the
            // synchronous `load` above, which paints the grid without waiting on a health read.
            .task {
                await model.loadHealthReadings()
            }
    }

    /// A line gets its tree; `Others` has no edges to draw, so it gets a flat grid.
    @ViewBuilder
    private func destination(for section: DexSection) -> some View {
        if section.isLine {
            EvolutionTreeView(nodes: section.nodes, rows: section.rows)
                .navigationTitle(section.title)
        } else {
            DexGridView(rows: section.rows)
                .navigationTitle(section.title)
        }
    }

    #if DEBUG
    /// The line `-dexLineDemo` opens: by default the Digital Monster Ver.1 tree, because it was the
    /// first shipped line that branches, so a screenshot of it shows a fork and its converging
    /// connectors rather than a straight ladder. `-dexLineDemo=<line>` opens another — every Phase E
    /// story adds a tree that has to be looked at at least once, and US-133 found a whole-tree
    /// black screen that only a screenshot could catch. Falls back to the first line so the arg
    /// still lands somewhere if the id is wrong.
    private var demoSection: DexSection? {
        let requested = CommandLine.arguments
            .first { $0.hasPrefix("-dexLineDemo=") }?
            .replacingOccurrences(of: "-dexLineDemo=", with: "") ?? "dmc-v1"
        return model.sections.first { $0.id == requested } ?? model.sections.first
    }
    #endif
}

/// A flat grid of Dex cells: the Dex root over the whole roster, and `Others` over the graph nodes
/// no line draws.
///
/// A `LazyVGrid` inside a `ScrollView`, which is what makes 1,022 entries affordable: only the
/// cells on screen are built, so only their sprites are ever decoded.
struct DexGridView: View {
    let rows: [DexRow]

    /// Whether `-dexDetailDemo` opens a detail sheet over this grid. True only for the Dex root,
    /// so the flag lands on one screen rather than re-firing on every grid pushed after it.
    var selectsDemoRow = false

    /// What the detail sheet's evolution hints are warmed up against. `.unknown` — every hint at
    /// its coldest — for the grids that are not the Dex root and have no model to ask.
    var context: ConditionContext = .unknown

    /// The line trees the detail sheet can push through to. Empty for a grid with no model to ask —
    /// which degrades to a sheet with no tree affordance, the same thing a roster-only Digimon gets,
    /// rather than to a link onto an empty tree.
    var sections: [DexSection] = []

    @State private var selected: DexRow?

    /// Three 32pt columns fit a 41mm watch, the narrowest screen the app supports.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    /// What the detail sheet resolves a row's evolution candidates against.
    ///
    /// Computed rather than built in an `init` because `rows` arrives empty and is replaced once
    /// `model.load()` runs, so a dictionary built at init would still be the empty one. It is
    /// evaluated only inside the `sheet` closure, so the cost is paid when a sheet opens, not on
    /// every scroll — and 1,022 inserts is microseconds either way.
    private var rowsById: [String: DexRow] {
        Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(rows) { row in
                        Button {
                            selected = row
                        } label: {
                            DexCell(row: row)
                        }
                        .buttonStyle(.plain)
                        // Undiscovered entries are still tappable, but there is nothing to tell.
                        .disabled(!row.isDiscovered)
                        .id(row.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            #if DEBUG
            // Both hooks, because the grid appears BEFORE it has any rows: `DexView.onAppear` is
            // what calls `model.load()`, and this view's own `onAppear` beats it. Firing on
            // `rows.count` as well is what makes the flags land on the loaded grid rather than on
            // an empty one.
            .onAppear { applyScreenshotFlags(scroller) }
            .onChange(of: rows.count) { _, _ in applyScreenshotFlags(scroller) }
            #endif
        }
        .sheet(item: $selected) { row in
            // A stack of its OWN rather than the Dex's, because a sheet is not on the presenting
            // stack: a `NavigationLink` inside one with no stack around it draws as a dead label.
            // The tree is pushed within the sheet, so closing the sheet closes the whole detour and
            // the grid is never left buried under it.
            NavigationStack {
                DexDetailView(row: row, pool: rowsById, context: context, sections: sections)
            }
        }
    }

    #if DEBUG
    private func applyScreenshotFlags(_ scroller: ScrollViewProxy) {
        selectFirstDiscoveredIfRequested()
        scrollToTheEndIfRequested(scroller)
    }

    /// Debug-only: sets exactly the state a tap sets, so the detail sheet can be screenshotted.
    /// `simctl` has no touch command and Simulator UI scripting needs an accessibility grant this
    /// machine does not have, so a real tap cannot be synthesised. Compiled out of release builds.
    private func selectFirstDiscoveredIfRequested() {
        guard selectsDemoRow else { return }
        if CommandLine.arguments.contains("-dexDetailDemo") {
            selected = rows.first { $0.isDiscovered }
        } else if CommandLine.arguments.contains("-dexEmptyDetailDemo") {
            // A roster entry in no evolution line, which is ~930 of the 1,022 — the only way to see
            // the "No evolutions recorded." branch, since `-dexDetailDemo` lands on Agumon and
            // Agumon branches three ways.
            selected = rows.first { $0.id == "aquilamon" }
        } else if CommandLine.arguments.contains("-dexWidestDetailDemo") {
            // The widest evolution grid the shipped file holds — five candidates since US-134,
            // which is the case `DexEvolutionCandidateTests` claims still fits two rows of the
            // three-column grid. The ceiling has been raised twice now and each raise is a claim
            // about this screen, so there has to be a way to photograph it.
            selected = rows.first { $0.id == "gabumon" }
        } else if CommandLine.arguments.contains("-dexUnmetDetailDemo") {
            // The sheet of an entry that has NEVER been met, which no tap can reach — the grid
            // disables undiscovered cells. US-088 withholds the type badges here, and "shows
            // neither" is a claim only a screenshot of this state can settle.
            selected = rows.first { !$0.isDiscovered }
        }
    }

    /// Debug-only: jumps to the last cell of the grid, 340-odd rows down. `simctl` has no scroll
    /// command any more than it has a tap, so this is the only way to see that the far end of a
    /// 1,022-cell grid builds and draws at all — the same trick, and the same reason, as
    /// `EvolutionTreeView.scrollToTheBranchIfRequested`. Compiled out of release builds.
    private func scrollToTheEndIfRequested(_ scroller: ScrollViewProxy) {
        guard CommandLine.arguments.contains("-dexScrollDemo"), let last = rows.last else { return }
        scroller.scrollTo(last.id, anchor: .bottom)
    }
    #endif
}

/// One grid cell: the Digimon's idle sprite, or a placeholder if it has never been met.
private struct DexCell: View {
    let row: DexRow

    var body: some View {
        Group {
            if row.isDiscovered {
                IdleSpriteView(stage: row.stage.rawValue, name: row.spriteFile)
            } else {
                // A "?" rather than a silhouette: a silhouette would have to be derived from the
                // sprite, which would mean decoding the very art this screen is withholding.
                Text("?")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        // The unmet cell is dimmed as a whole, tile and all. On a grid that is mostly unmet — 1,022
        // entries against the handful one game discovers — a "?" alone reads as the pattern and the
        // met sprites as the exception; dropping the tile back makes the met ones the figure.
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(.white.opacity(row.isDiscovered ? 0.08 : 0.03)))
        .opacity(row.isDiscovered ? 1 : 0.55)
    }
}

/// What is known about one discovered Digimon, and what it can still become.
struct DexDetailView: View {
    let row: DexRow

    /// Rows to resolve this entry's edge targets against, keyed by id — the surrounding grid's or
    /// tree's rows. A candidate needs a discovery date to know whether to show its art, and only a
    /// row carries one.
    ///
    /// Defaults to empty, which degrades to every candidate drawn as undiscovered rather than to no
    /// section at all: the names are the part being withheld, and withholding one the player has
    /// actually earned is a smaller wrong than losing the whole list.
    var pool: [String: DexRow] = [:]

    var graph: EvolutionGraph = .bundled

    /// Where the badge row's element and attribute come from (US-088). Injectable alongside
    /// `graph` because the two are asked together — `ElementCatalog.type(for:in:)` resolves a
    /// Digimon's line off the graph, so a test that swaps one and not the other is testing a
    /// catalog against a roster it was not authored for.
    var catalog: ElementCatalog = .bundled

    /// Where the attack row's projectile and signature come from (US-089). Injectable beside
    /// `graph` and `roster` for the same reason `catalog` is — `MoveCatalog.move(for:in:roster:)`
    /// resolves a Digimon's line off the graph and its stage off the roster, so the three travel
    /// together or they answer for a Digimon that is not the one on screen.
    var moves: MoveCatalog = .bundled

    /// The roster the attack row falls back to for a stage. Needed because ~930 of the 1,022
    /// entries have no graph node at all, and the stage tier is the floor that keeps every one of
    /// them throwing something.
    var roster: Roster = .bundled

    /// The totals the hints are resolved against. `.unknown` shows every hint at its coldest,
    /// which is what a preview or a grid with no model gets.
    var context: ConditionContext = .unknown

    /// The Dex's line sections, which `lineSection` picks this Digimon's tree out of.
    ///
    /// Empty by default, and empty is what the tree screen's own sheet passes — so opening a cell
    /// FROM a tree offers no link back to the tree it was opened from. That is the wanted
    /// behaviour, not a gap: the affordance exists to reach a tree from the flat grid.
    var sections: [DexSection] = []

    /// Whether the owning line's tree is pushed. Set by the link, and by `-dexTreeDemo`.
    @State private var showsTree = false

    /// The branch the player has tapped, as a `DexCandidate.ID`, or nil for the flat list.
    ///
    /// State of THIS view and nowhere else, which is what makes US-111's "selection resets when the
    /// sheet is dismissed and reopened" true by construction: `DexGridView` presents the sheet with
    /// `.sheet(item:)`, so dismissing it destroys this view and reopening builds a fresh one. A
    /// selection parked on the model or on the row would survive that and reopen the sheet in a
    /// filtered state, which looks like a bug rather than like a filter.
    @State private var selectedBranch: DexCandidate.ID?

    /// Cheap enough to recompute as `body` re-runs: at most three edges and a dictionary hit each.
    private var candidates: [DexCandidate] {
        DexRow.candidates(of: row.id, in: graph, resolvedAgainst: pool)
    }

    /// What the hint section says: the flat all-branches list, or the tapped branch's own criteria.
    /// Both the flattening and the reasoning behind it now live in `DexHintList`, which is pure and
    /// testable without a sheet.
    private var hintList: DexHintList? {
        DexHintList.list(selecting: selectedBranch, from: candidates)
    }

    /// Three columns, as on the Dex grid, so one to three candidates are a single line that fits a
    /// 41mm screen and a fourth wraps onto a second line the sheet scrolls to reach.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    /// Tightened in US-064 so a row of candidates clears the fold on a 41mm watch, which has about
    /// 215pt of height and lost 55 of it to the sheet's own close-button chrome. The hero dropped
    /// from 4x to 3x and the stage and date merged onto one 10pt line. Screenshots on 41mm settled
    /// each of those, not arithmetic: the first two attempts put the section below the fold and
    /// then clipped the tiles halfway.
    var body: some View {
        ScrollViewReader { scroller in
            sheet
            #if DEBUG
            // Debug-only, and the same trick and the same reason as
            // `EvolutionTreeView.scrollToTheBranchIfRequested`: the hint list sits below a 41mm
            // fold by design, `simctl` has no scroll command, and this is the only way to
            // screenshot it. Compiled out of release builds.
            .onAppear {
                selectBranchIfRequested()
                // Follows the link without a tap, so grid -> detail -> tree can be screenshotted
                // end to end. It sets the same state the button does, so what the screenshot proves
                // is the real path and not a second one built for the camera.
                if CommandLine.arguments.contains("-dexTreeDemo") {
                    showsTree = true
                } else if CommandLine.arguments.contains("-dexTreeLinkDemo") {
                    scroller.scrollTo(Self.treeLinkAnchor, anchor: .bottom)
                } else if Self.scrollsToHints {
                    scroller.scrollTo(Self.hintsAnchor, anchor: .bottom)
                }
            }
            #endif
        }
    }

    #if DEBUG
    /// Whether the hint list is what is being screenshotted. Every US-111 branch demo scrolls there
    /// too, since a selection nobody can see settles nothing.
    private static var scrollsToHints: Bool {
        ["-dexRevealDemo", "-dexBranchDemo", "-dexBranchNoneDemo", "-dexBranchToggleDemo"]
            .contains { CommandLine.arguments.contains($0) }
    }

    /// Debug-only: US-111's selection, set by calling `toggle(_:)` — the same function a tap calls,
    /// once for `-dexBranchDemo` and twice for `-dexBranchToggleDemo`, so the deselected screenshot
    /// comes from a second tap on the selected cell rather than from never having selected at all.
    /// `simctl` has no touch command; see `DexGridView.selectFirstDiscoveredIfRequested`.
    /// Compiled out of release builds.
    private func selectBranchIfRequested() {
        let args = CommandLine.arguments
        let target: DexCandidate?
        if args.contains("-dexBranchNoneDemo") {
            // The unconditional branch — Numemon out of Agumon — which is the only way to see the
            // `DexHintList.nothingRequired` line.
            target = candidates.first { $0.conditions.isEmpty }
        } else if args.contains("-dexBranchDemo") || args.contains("-dexBranchToggleDemo") {
            target = candidates.first { !$0.conditions.isEmpty }
        } else {
            target = nil
        }
        guard let target else { return }
        toggle(target)
        if args.contains("-dexBranchToggleDemo") { toggle(target) }
    }
    #endif

    /// Split out of `body` only so the debug scroll hook above has one view to attach to.
    private var sheet: some View {
        ScrollView {
            VStack(spacing: 2) {
                IdleSpriteView(stage: row.stage.rawValue, name: row.spriteFile, scale: 3)

                Text(row.displayName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                typeBadges

                attackRow

                evolutions

                lineTreeLink
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The line whose tree this Digimon belongs on, or nil for the ~930 roster-only entries and the
    /// `dexOnly` ones — both of which get no affordance at all rather than a link onto an empty
    /// tree.
    private var lineSection: DexSection? {
        DexSection.line(containing: row.id, in: sections)
    }

    /// The way through to the tree: US-067's whole point, and the reason `EvolutionTreeView` was
    /// kept when US-063 took the line list off the Dex root.
    ///
    /// Last on the sheet, under the candidates and the hints, because those answer "what next" —
    /// the question this screen is opened to ask — and US-064 spent two screenshots getting the
    /// candidate row above a 41mm fold. The tree answers the broader "what is the shape of all
    /// this", which is worth a scroll.
    /// A `Button` plus `navigationDestination(isPresented:)` rather than the `NavigationLink` this
    /// obviously wants to be, for the reason `-dexDetailDemo` exists at all: `simctl` has no touch
    /// command, so a link only a tap can follow is a screen that can never be screenshotted. One
    /// destination and one piece of state, which the debug hook below sets exactly as a tap does.
    @ViewBuilder
    private var lineTreeLink: some View {
        if let section = lineSection {
            Button {
                showsTree = true
            } label: {
                Label("\(section.title) line", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11))
            }
            .padding(.top, 6)
            .id(Self.treeLinkAnchor)
            .navigationDestination(isPresented: $showsTree) {
                EvolutionTreeView(nodes: section.nodes, rows: section.rows)
                    .navigationTitle(section.title)
            }
        }
    }

    /// Scroll target for the tree link. Read by the debug hook in `body`.
    private static let treeLinkAnchor = "tree-link"

    /// What this Digimon is, on both type axes (US-088) — under the name and its stage, so the
    /// identity block reads name, when you met it, what it is, and only then what it can become.
    ///
    /// Absent entirely for an unmet entry rather than dimmed: see `DexTypeBadges.type(for:)`. It
    /// costs `TypeBadgeLayout.budget` of the sheet's height, which is what keeps the candidate
    /// tiles US-064 fought for above the 41mm fold.
    @ViewBuilder
    private var typeBadges: some View {
        if let type = DexTypeBadges.type(for: row, in: graph, catalog: catalog) {
            TypeBadgeRow(type: type)
        }
    }

    /// What this Digimon throws (US-089) — directly under the type badges, because element,
    /// attribute and attack are three answers to the one question "what is this thing in a fight",
    /// and the `Divider()` below opens the separate question of what it becomes.
    ///
    /// Absent entirely for an unmet entry rather than dimmed: see `DexMoveRow.move(for:)`. Costs
    /// `MoveRowLayout.budget`, the second charge in a row against a 41mm sheet with very little
    /// left under the candidate tiles.
    @ViewBuilder
    private var attackRow: some View {
        if let move = DexMoveRow.move(for: row, in: graph, roster: roster, catalog: moves) {
            MoveRow(move: move)
        }
    }

    /// Stage and first sighting on one line, which is worth a whole 13pt line of a 215pt screen.
    /// "met" rather than "first met" so the pair still fits 41mm without wrapping.
    private var subtitle: String {
        guard let firstDiscovered = row.firstDiscovered else { return row.stage.displayName }
        let date = firstDiscovered.formatted(date: .abbreviated, time: .omitted)
        return "\(row.stage.displayName) · met \(date)"
    }

    @ViewBuilder
    private var evolutions: some View {
        Divider()

        Text("Evolves into")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

        sleepBar

        if candidates.isEmpty {
            // Said out loud rather than left as a bare heading. Most of the roster has no authored
            // line, so an empty section here would be the common case and would read as a bug.
            Text("No evolutions recorded.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        } else {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(candidates) { candidate in
                    // Tappable whether or not the target has been met, and NOT `.disabled` for an
                    // undiscovered one the way the Dex grid's cells are: a "?" has no detail sheet
                    // to open, but it does have conditions, and asking what the "?" wants is the
                    // whole of US-111.
                    Button {
                        toggle(candidate)
                    } label: {
                        DexCandidateCell(row: candidate.row, isEarned: isEarned(candidate),
                                         isSelected: selectedBranch == candidate.id)
                    }
                    .buttonStyle(.plain)
                }
            }

            hints
        }
    }

    /// The accumulated-sleep gate as a dash bar (US-183): `required` dashes, `earned` solid, the
    /// rest outline, no numbers — so the player reads how much sleep this Digimon still owes its next
    /// form. Drawn only when a branch out of here gates on accumulated sleep (`SleepGate`); every
    /// other Digimon shows nothing here. `earned` comes from the SAME lifetime total the gate
    /// compares, so the bar and the branch's green check can never disagree.
    @ViewBuilder
    private var sleepBar: some View {
        if let required = SleepGate.requiredHours(in: candidates.flatMap(\.conditions)) {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                DashBar(filled: SleepGate.earnedHours(in: context), total: required, tint: .indigo)
            }
            .padding(.horizontal, 4)
            .accessibilityLabel("Sleep to evolve")
        }
    }

    /// A tap on a candidate: select it, or clear the selection if it was already selected.
    ///
    /// Assigning straight over an existing selection is what moves the selection from one candidate
    /// to another in one step — there is no deselect-then-select, so no frame in which the list is
    /// briefly the flat one.
    private func toggle(_ candidate: DexCandidate) {
        selectedBranch = selectedBranch == candidate.id ? nil : candidate.id
    }

    /// Scroll target for the hint list. Read by the debug hook in `body`.
    private static let hintsAnchor = "hints"

    /// Whether this branch's criteria are all satisfied — the green cell.
    ///
    /// An UNCONDITIONAL edge is deliberately not marked, even though `ConditionReveal.allMet` says
    /// true of it and is right to: vacuous truth is the correct answer to "is anything outstanding"
    /// and the wrong thing to put a checkmark on. Every node's junk default is unconditional, so
    /// marking those would tick the one branch the player is trying to AVOID, on every screen, from
    /// the first launch — and a mark that is always on for two of three cells teaches nothing.
    /// The screenshot on 41mm is what surfaced this: Numemon and Meramon both came up green.
    private func isEarned(_ candidate: DexCandidate) -> Bool {
        !candidate.conditions.isEmpty && ConditionReveal.allMet(candidate.conditions, in: context)
    }

    /// The reveal list: one warmed-up line per criterion, of the tapped branch or of all of them.
    /// Omitted entirely — heading and all — when the flat list has nothing in it, which is the case
    /// for branches gated only by energy and care and so for most of the graph.
    ///
    /// The heading comes from the list rather than being written here, because which heading is
    /// right depends on which list this is. See `DexHintList.branchHeading`.
    @ViewBuilder
    private var hints: some View {
        if let list = hintList {
            Text(list.heading)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(list.lines.enumerated()), id: \.offset) { _, line in
                    switch line {
                    case .condition(let condition):
                        ConditionHintRow(condition: condition, context: context)
                    case .plain(let sentence):
                        Text(sentence)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 4)
            .id(Self.hintsAnchor)
        }
    }
}

/// One criterion, said as flavour text and marked with how close it is.
///
/// The level is carried by a SYMBOL rather than by a number or a bar, because a bar has a length
/// and a length is a percentage read off with a ruler. A symbol has three states and no more.
///
/// Not `private` since US-121: the map detail draws a Digitama slot's criteria with THIS row rather
/// than a copy of it, which is the strongest available form of that story's "identical wording to
/// the Dex's evolution hints" — a second implementation could drift a word or a threshold, and the
/// player would be reading two different promises about the same `ConditionReveal` output.
struct ConditionHintRow: View {
    let condition: EvolutionCondition
    let context: ConditionContext

    private var level: RevealLevel { ConditionReveal.level(of: condition, in: context) }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 9))
                .foregroundStyle(tint)

            Text(ConditionReveal.line(for: condition, in: context))
                .font(.system(size: 10))
                .foregroundStyle(level == .far ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var symbolName: String {
        switch level {
        case .far: return "circle"
        // A flame and not a half-filled anything: a half-filled glyph would draw the very fraction
        // the hint refuses to say.
        case .close: return "flame.fill"
        case .met: return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch level {
        case .far: return .secondary
        case .close: return .orange
        case .met: return .green
        }
    }
}

/// One Digimon this entry can evolve into: its art and name once met, a bare "?" until then.
///
/// The name is withheld, not just the sprite. A Dex that named the thing you have not found yet
/// would be answering the question the Dex exists to make you go and answer.
private struct DexCandidateCell: View {
    let row: DexRow

    /// Every criterion on the edge that reaches this candidate currently holds.
    ///
    /// Drawn as a green outline and a corner checkmark, and NOT as the cell brightening — the cell
    /// already uses brightness for discovered-vs-not, and a second meaning on one channel would
    /// make an undiscovered-but-earned branch indistinguishable from a discovered-but-unearned one.
    /// That pair is exactly the interesting case: a branch you have qualified for and never seen.
    var isEarned = false

    /// Whether this is the branch the player has tapped (US-111).
    ///
    /// Marked with a ring INSIDE the tile, in white, which is a third channel and had to be: the
    /// cell's brightness already means discovered-or-not and its outer outline already means
    /// earned-or-not, so a second meaning on either would make an earned-but-unselected cell
    /// indistinguishable from a selected one — and that pair is on screen together the moment a
    /// player taps the branch they have qualified for.
    var isSelected = false

    var body: some View {
        VStack(spacing: 0) {
            if row.isDiscovered {
                IdleSpriteView(stage: row.stage.rawValue, name: row.spriteFile)

                Text(row.displayName)
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("?")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(.white.opacity(row.isDiscovered ? 0.08 : 0.03)))
        .overlay(alignment: .topTrailing) {
            if isEarned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
                    .padding(1)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(.green, lineWidth: isEarned ? 1 : 0))
        // The earned mark stays at full strength on an undiscovered cell: dimming it would sink
        // the one thing this cell has to say underneath the dimming that means "not met yet".
        .opacity(row.isDiscovered || isEarned ? 1 : 0.55)
        // Applied AFTER the opacity rather than exempted inside it, so selecting an unmet "?"
        // brightens nothing: a selected "?" is exactly as dim as any other "?", and the ring is
        // the only thing that changed. Inset by 2 so it never sits on top of the earned outline —
        // a cell can be both at once, and both have to stay readable.
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.white, lineWidth: 1)
                    .padding(2)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DexView(model: DexModel())
    }
}
