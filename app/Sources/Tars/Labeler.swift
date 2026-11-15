import Foundation

/// The prompts that ask an AI for labels, the same kinds pipeline/generate.py writes: one-skill phrasings, hard
/// multi-step sentences, and near misses plus chatter. The MCP server hands agents the same instructions.
enum LabelPrompt {
    static let styles = [
        "short and blunt, 1-4 words", "polite and complete, with please or could you", "casual slang and filler (like, um, ngl)",
        "indirect: describe the goal or the problem instead of naming the action", "mid-thought, starting with 'okay so' or 'wait'",
        "vague references: this, that, it, over there", "naming a specific app or window", "questions phrased as requests: can you, is there a way to",
        "impatient, 'just' and 'already'", "long and rambly with the request in the middle", "speech-to-text errors: dropped words, homophones, no punctuation",
        "non-native English, simple grammar", "tired late-night mumbling, lowercase",
    ]

    static let format = """
    Return ONLY a JSON array, no prose. Each item: {"said": "<what the user said>", "steps": [{"text": "<exact substring of said>", "skill": "<skill key or none>"}]}
    Rules: step texts are exact substrings of "said", in order, without joining words (and, then, to); one step per separate request; \
    use "none" for a part that is chatter or not a request.
    """

    static func skillList(_ c: Catalog, only: Set<String>? = nil) -> String {
        c.skills.filter { only?.contains($0.key) ?? true }
            .map { "- \($0.key) (\($0.family)): \($0.name). e.g. \($0.examples.prefix(3).joined(separator: "; "))" }.joined(separator: "\n")
    }

    static func context(_ c: Catalog) -> String {
        c.context.isEmpty ? "You are writing training data for \(c.assistant), a voice assistant. Sentences are speech-to-text output: often no punctuation, sometimes misheard words." : c.context
    }

    /// The schema and guidance get_label_schema returns, and the base of every prompt.
    static func schema(_ c: Catalog) -> String {
        """
        \(context(c))

        Write commands a user might say to \(c.assistant), each labeled with its steps and the skill for each step.
        Make them hard and realistic: varied vocabulary, indirect goals ("it's way too loud" for volume), vague references, filler, \
        self-corrections, speech-to-text mistakes; multi-step sentences with missing joiners ("open the browser move it left"), \
        "to" used as "and", back-references ("move it", "that song"), titles that contain command words ("play Stop Making Sense"); \
        near misses between similar skills; and about one in six that are not commands at all (skill "none").

        \(format)

        Skills:
        \(skillList(c))
        """
    }

    enum Kind: String, CaseIterable { case single, multi, confuse }

    static func prompt(_ kind: Kind, catalog c: Catalog, focus: [Skill], n: Int, rng: inout some RandomNumberGenerator) -> String {
        let style = styles.shuffled(using: &rng).prefix(4).joined(separator: " | ")
        switch kind {
        case .single:
            let s = focus[0]
            return """
            \(context(c))

            Write \(n) different things the user might say that should be handled by this one skill:
              \(s.key): \(s.name) (family: \(s.family)). Known examples: \(s.examples.joined(separator: "; "))
            Make them hard and realistic: spread across these speaking styles: \(style). Avoid the words in the known examples for at \
            least half. Include indirect goals, vague references, filler, self-corrections and a few speech-to-text mistakes. About a fifth \
            should contain a word that belongs to a different skill but still mean this one. One action per sentence: one step whose text is the whole sentence.

            \(format)
            """
        case .multi:
            return """
            \(context(c))

            Write \(n) sentences where the user asks for 2 to 4 things in one breath, across different skills. Use each of these at least once:
            \(skillList(c, only: Set(focus.map(\.key))))
            Make them hard to split: joiners vary ("and", "then", commas, nothing at all, "and go", "to" used as "and"); later steps refer \
            back (it, that, this window); names and queries containing command words stay inside their step; mix questions and actions. \
            Speaking styles: \(style).

            \(format)

            All skills:
            \(skillList(c))
            """
        case .confuse:
            let pairs = stride(from: 0, to: focus.count - 1, by: 2).map { "- \(focus[$0].key) vs \(focus[$0 + 1].key)" }.joined(separator: "\n")
            return """
            \(context(c))

            Write \(n) short commands that sit right on the line between two skills that are easy to confuse, roughly equal numbers both ways:
            \(pairs)
            Also include about a sixth that are not commands at all (skill "none"): talking to someone else, reading aloud, thinking out loud, \
            "never mind", mentioning apps without asking for anything.

            \(format)

            All skills:
            \(skillList(c))
            """
        }
    }

    /// The first JSON array in a reply (models sometimes wrap it in prose or a code fence).
    static func parse(_ text: String) -> [[String: Any]]? {
        guard let a = text.firstIndex(of: "["), let b = text.lastIndex(of: "]"), a < b else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text[a...b].utf8))) as? [[String: Any]]
    }
}

/// Asks the chosen provider for labels in batches until the target is reached or the user stops.
@MainActor @Observable
final class Generator {
    var running = false
    var asked = 0
    var failed = 0
    var lastError: String?
    var lastRejected: [String] = []
    private var task: Task<Void, Never>?

    func start(_ app: AppModel, target: Int, perBatch: Int = 25, parallel: Int = 3) {
        guard !running else { return }
        running = true
        asked = 0; failed = 0; lastError = nil
        let provider = AISettings.provider
        task = Task {
            var rng = SystemRandomNumberGenerator()
            var round = 0
            while !Task.isCancelled, app.labels.count < target {
                // Fill the thinnest skills first; rotate the three kinds.
                let counts = app.skillCounts
                let thin = app.catalog.skills.sorted { (counts[$0.key] ?? 0) < (counts[$1.key] ?? 0) }
                let prompts: [String] = (0..<parallel).map { i in
                    let kind = LabelPrompt.Kind.allCases[(round + i) % 3]
                    let focus = kind == .single ? [thin[(round + i) % max(1, min(thin.count, 8))]] : Array(thin.prefix(12).shuffled(using: &rng).prefix(kind == .multi ? 5 : 8))
                    return LabelPrompt.prompt(kind, catalog: app.catalog, focus: focus, n: perBatch, rng: &rng)
                }
                round += parallel
                await withTaskGroup(of: Result<String, Error>.self) { group in
                    for p in prompts { group.addTask { do { return .success(try await AI.ask(provider, p)) } catch { return .failure(error) } } }
                    for await r in group {
                        asked += 1
                        switch r {
                        case .success(let text):
                            guard let items = LabelPrompt.parse(text) else { failed += 1; lastError = "The answer had no JSON array"; continue }
                            let intake = Intake.check(items, catalog: app.catalog, existing: app.labels, source: provider.short.lowercased())
                            app.add(intake.accepted)
                            lastRejected = intake.rejected
                        case .failure(let e):
                            failed += 1
                            lastError = e.localizedDescription
                        }
                    }
                }
                if failed >= 3 && failed == asked { break }   // nothing works: stop instead of burning the user's quota
            }
            running = false
        }
    }

    func stop() { task?.cancel(); task = nil; running = false }
}
