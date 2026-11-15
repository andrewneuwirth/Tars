import Foundation

/// The catalog and labels on disk, plus the generator and trainer. Demo mode (previews) never reads or writes files.
@MainActor @Observable
final class AppModel {
    var catalog: Catalog { didSet { if !demo, catalog != oldValue { Files.save(catalog) } } }
    var labels: [Labeled] = []
    let generator = Generator()
    let trainer = Trainer()
    let demo: Bool
    private var labelsDate: Date?
    private var watcher: Timer?

    init(demo: Bool = false) {
        self.demo = demo
        if demo {
            catalog = Demo.catalog
            labels = Demo.labels
            Demo.fill(trainer)
            return
        }
        catalog = Files.loadCatalog() ?? Catalog()
        if !FileManager.default.fileExists(atPath: Files.catalog.path) { Files.save(catalog) }
        reloadLabels()
        trainer.refresh()
        // Labels from the MCP server arrive in the same file; pick them up.
        watcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in if Files.modified(Files.labels) != self.labelsDate { self.reloadLabels() } }
        }
    }

    func reloadLabels() {
        labels = Files.loadLabels()
        labelsDate = Files.modified(Files.labels)
    }

    func add(_ new: [Labeled]) {
        guard !new.isEmpty else { return }
        labels += new
        guard !demo else { return }
        Files.append(new)
        labelsDate = Files.modified(Files.labels)
    }

    /// Rewrites the file after an edit or delete.
    // shortcut: an MCP submission landing between the last reload and this write is lost; fine for one person's app, a lock file if it ever matters.
    func saveLabels() {
        guard !demo else { return }
        if Files.modified(Files.labels) != labelsDate {   // pick up appended lines first
            let known = Set(labels.map(\.id))
            labels += Files.loadLabels().filter { !known.contains($0.id) && !deleted.contains($0.id) }
        }
        Files.save(labels)
        labelsDate = Files.modified(Files.labels)
    }
    private var deleted = Set<UUID>()

    func delete(_ ids: Set<UUID>) {
        deleted.formUnion(ids)
        labels.removeAll { ids.contains($0.id) }
        saveLabels()
    }

    func update(_ l: Labeled) {
        guard let i = labels.firstIndex(where: { $0.id == l.id }) else { return }
        labels[i] = l
        saveLabels()
    }

    var skillCounts: [String: Int] {
        labels.reduce(into: [:]) { d, l in for s in l.steps { d[s.skill, default: 0] += 1 } }
    }

    /// Labels that no longer fit the catalog (a skill was renamed or removed).
    var invalid: [Labeled] { labels.filter { $0.problem(in: catalog) != nil } }

    func loadExample() {
        catalog = Demo.catalog
    }
}
