import Foundation

// The catalog and labels, in exactly the JSON the Python pipeline reads (tars/catalog.py, pipeline/build.py --labels).

struct Family: Identifiable, Hashable { var key: String; var description: String; var id: String { key } }

struct Skill: Codable, Identifiable, Hashable {
    var key: String
    var family: String
    var name: String
    var examples: [String]
    var id: String { key }
}

struct Catalog: Codable, Equatable {
    var assistant = "Tars"
    var context = ""
    var families: [Family] = [Family(key: "none", description: Catalog.noneDescription)]
    var skills: [Skill] = []

    static let noneDescription = "Not a request for the computer: talking to someone else, thinking out loud, reading aloud, never mind"

    enum CodingKeys: String, CodingKey { case assistant, context, families, skills }

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        assistant = try c.decodeIfPresent(String.self, forKey: .assistant) ?? "Tars"
        context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
        let fams = try c.decode([String: String].self, forKey: .families)
        families = fams.keys.sorted { ($0 == "none" ? 1 : 0, $0) < ($1 == "none" ? 1 : 0, $1) }.map { Family(key: $0, description: fams[$0]!) }
        skills = try c.decode([Skill].self, forKey: .skills)
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(assistant, forKey: .assistant)
        try c.encode(context, forKey: .context)
        try c.encode(Dictionary(uniqueKeysWithValues: families.map { ($0.key, $0.description) }), forKey: .families)
        try c.encode(skills, forKey: .skills)
    }

    func family(of skill: String) -> String? { skill == "none" ? "none" : skills.first { $0.key == skill }?.family }

    /// What the pipeline would refuse, in words; empty when it can train.
    var problems: [String] {
        var out: [String] = []
        if !families.contains(where: { $0.key == "none" }) { out.append("The catalog needs a \"none\" family.") }
        let keys = Set(families.map(\.key))
        for s in skills where !keys.contains(s.family) { out.append("\(s.name) uses a family that doesn't exist (\(s.family)).") }
        if Set(skills.map(\.key)).count != skills.count { out.append("Two skills share a key.") }
        if skills.count < 2 { out.append("Add at least two skills.") }
        return out
    }

    /// A key from a name: "Play music" → "play_music".
    static func key(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression).trimmingCharacters(in: ["_"])
    }
}

struct Step: Codable, Hashable { var text: String; var skill: String }

/// One labeled sentence. `set`: train, test (held out for the verdict) or real (the user's own sentences).
struct Labeled: Codable, Identifiable, Hashable {
    var id = UUID()
    var said: String
    var steps: [Step]
    var set = "train"
    var source = ""

    var summary: String { steps.map(\.skill).joined(separator: " → ") }

    /// About one in ten labels is held out for testing, decided by the sentence so it never changes.
    static func defaultSet(_ said: String) -> String {
        Array(norm(said).utf8).reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) } % 10 == 0 ? "test" : "train"
    }

    static func norm(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.union(["'"]).inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension Labeled {
    /// Why the pipeline couldn't use this label, or nil when it can: known skills, and step texts found in order in `said`
    /// (the same rule as pipeline/build.py's locate).
    func problem(in catalog: Catalog) -> String? {
        if said.trimmingCharacters(in: .whitespaces).isEmpty { return "said is empty" }
        if steps.isEmpty { return "no steps" }
        var rest = said.lowercased()[...]
        for s in steps {
            if catalog.family(of: s.skill) == nil { return "unknown skill \(s.skill)" }
            let t = s.text.trimmingCharacters(in: .whitespaces).lowercased()
            guard !t.isEmpty, let r = rest.range(of: t) else { return "step \"\(s.text)\" isn't in the sentence" }
            rest = rest[r.upperBound...]
        }
        return nil
    }
}

/// Files under ~/Library/Application Support/Tars (or $TARS_HOME, for tests): catalog.json, labels.jsonl, the training
/// environment, the models, and the training data and runs.
enum Files {
    static var root: URL {
        let u = ProcessInfo.processInfo.environment["TARS_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tars")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var catalog: URL { root.appendingPathComponent("catalog.json") }
    static var labels: URL { root.appendingPathComponent("labels.jsonl") }
    static var data: URL { root.appendingPathComponent("data") }
    static var runs: URL { root.appendingPathComponent("runs") }
    static var progress: URL { root.appendingPathComponent("progress.json") }
    static var stop: URL { root.appendingPathComponent("STOP") }   // pipeline/train.py stops cleanly when this appears
    static var checkpoint: URL { root.appendingPathComponent("checkpoints/tars") }
    static var candidate: URL { root.appendingPathComponent("checkpoints/tars-candidate") }
    static var log: URL { root.appendingPathComponent("run.log") }
    static var env: URL { root.appendingPathComponent("env") }
    static var von: URL { root.appendingPathComponent("von") }
    static var baseModel: URL { root.appendingPathComponent("models/von-1.2") }
    static var tarsModel: URL { root.appendingPathComponent("models/tars-0.4") }

    static func loadCatalog(_ url: URL = catalog) -> Catalog? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Catalog.self, from: $0) }
    }
    static func save(_ c: Catalog, to url: URL = catalog) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? e.encode(c).write(to: url, options: .atomic)
    }

    static func loadLabels(_ url: URL = labels) -> [Labeled] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(Labeled.self, from: Data($0.utf8)) }
    }
    static func line(_ l: Labeled) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return ((try? e.encode(l)) ?? Data()) + Data("\n".utf8)
    }
    static func save(_ labels: [Labeled], to url: URL = labels) {
        try? labels.reduce(into: Data()) { $0 += line($1) }.write(to: url, options: .atomic)
    }
    /// Appends without rewriting, so the MCP process and the app can both add labels.
    static func append(_ new: [Labeled], to url: URL = labels) {
        guard !new.isEmpty else { return }
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: new.reduce(into: Data()) { $0 += line($1) })
    }
    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// Labels a provider or an agent sent back: the valid new ones, and why the rest were dropped.
struct Intake {
    var accepted: [Labeled] = []
    var rejected: [String] = []

    /// Validates against the catalog and drops sentences already labeled (same words, ignoring case and punctuation).
    static func check(_ raw: [[String: Any]], catalog: Catalog, existing: [Labeled], source: String) -> Intake {
        var seen = Set(existing.map { Labeled.norm($0.said) })
        var out = Intake()
        for (i, item) in raw.enumerated() {
            guard let said = (item["said"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else { out.rejected.append("#\(i): no said"); continue }
            var steps = (item["steps"] as? [[String: Any]] ?? []).compactMap { s -> Step? in
                guard let t = s["text"] as? String, let k = s["skill"] as? String else { return nil }
                return Step(text: t.trimmingCharacters(in: .whitespaces), skill: k.trimmingCharacters(in: .whitespaces))
            }
            if steps.isEmpty, let k = item["skill"] as? String { steps = [Step(text: said, skill: k)] }   // single-skill shorthand
            let set = (item["set"] as? String).flatMap { ["train", "test", "real"].contains($0) ? $0 : nil } ?? Labeled.defaultSet(said)
            let l = Labeled(said: said, steps: steps, set: set, source: source)
            if let why = l.problem(in: catalog) { out.rejected.append("#\(i) \"\(said.prefix(60))\": \(why)"); continue }
            guard seen.insert(Labeled.norm(said)).inserted else { out.rejected.append("#\(i) \"\(said.prefix(60))\": duplicate"); continue }
            out.accepted.append(l)
        }
        return out
    }
}
