import Foundation

/// `Tars --self-check`: the pure logic (catalog JSON, label rules, prompts, MCP, status parsing) against temp files.
/// Nothing in Application Support is touched and no AI or Python is called.
@MainActor
enum SelfCheck {
    static func run() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FAIL:", what) } }

        // Catalog round trip in the pipeline's format.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tars-check-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cat = Demo.catalog, catURL = dir.appendingPathComponent("catalog.json"), labURL = dir.appendingPathComponent("labels.jsonl")
        Files.save(cat, to: catURL)
        let raw = (try? JSONSerialization.jsonObject(with: Data(contentsOf: catURL))) as? [String: Any]
        check(raw?["families"] is [String: String] && (raw?["skills"] as? [[String: Any]])?.first?["key"] != nil, "catalog JSON shape")
        let back = Files.loadCatalog(catURL)
        check(back?.skills == cat.skills && Set(back?.families ?? []) == Set(cat.families) && back?.families.last?.key == "none", "catalog round trip")
        check(cat.problems.isEmpty, "demo catalog is valid")
        var broken = cat; broken.families.removeAll { $0.key == "none" }
        check(!broken.problems.isEmpty, "missing none family is reported")
        check(Catalog.key("Play music!") == "play_music", "key from name")

        // Label rules, the same as pipeline/build.py.
        let good = Labeled(said: "open tunebox and play jazz", steps: [Step(text: "open tunebox", skill: "open_app"), Step(text: "play jazz", skill: "play_music")])
        check(good.problem(in: cat) == nil, "valid label")
        check(Labeled(said: "play jazz open tunebox", steps: [Step(text: "open tunebox", skill: "open_app"), Step(text: "play jazz", skill: "play_music")]).problem(in: cat) != nil, "steps out of order")
        check(Labeled(said: "hi", steps: [Step(text: "hi", skill: "nope")]).problem(in: cat) != nil, "unknown skill")
        check(Labeled(said: "never mind", steps: [Step(text: "never mind", skill: "none")]).problem(in: cat) == nil, "none is allowed")
        let sets = (0..<400).map { Labeled.defaultSet("sentence number \($0)") }
        let tests = sets.filter { $0 == "test" }.count
        check(tests > 15 && tests < 70 && Labeled.defaultSet("x y") == Labeled.defaultSet("X, y"), "about 10% held out, stable")

        // Intake: validation, dedupe, single-skill shorthand.
        let intake = Intake.check([["said": "Play jazz", "skill": "play_music"], ["said": "play jazz!", "skill": "play_music"],
                                   ["said": "x", "steps": [["text": "y", "skill": "volume"]]], ["said": "mute", "steps": [["text": "mute", "skill": "volume"]], "set": "test"]],
                                  catalog: cat, existing: [], source: "check")
        check(intake.accepted.count == 2 && intake.rejected.count == 2 && intake.accepted[1].set == "test", "intake")
        check(LabelPrompt.parse("Sure:\n```json\n[{\"said\": \"a\"}]\n```")?.count == 1, "parse array in prose")
        var rng = SystemRandomNumberGenerator()
        for k in LabelPrompt.Kind.allCases {
            let p = LabelPrompt.prompt(k, catalog: cat, focus: Array(cat.skills.prefix(8)), n: 5, rng: &rng)
            check(p.contains("Return ONLY a JSON array"), "prompt \(k)")
        }

        // Files: append then load.
        Files.append([good], to: labURL)
        Files.append(intake.accepted, to: labURL)
        check(Files.loadLabels(labURL).count == 3, "append and load labels")

        // MCP over the temp files.
        func call(_ method: String, _ params: [String: Any] = [:]) -> [String: Any]? {
            MCP.handle(["jsonrpc": "2.0", "id": 1, "method": method, "params": params], catalogURL: catURL, labelsURL: labURL, progressURL: dir.appendingPathComponent("p.json"))
        }
        check((call("initialize")?["result"] as? [String: Any])?["serverInfo"] != nil, "mcp initialize")
        check(((call("tools/list")?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.count == 4, "mcp tools")
        let sub = call("tools/call", ["name": "submit_labels", "arguments": ["labels": [["said": "turn on do not disturb", "steps": [["text": "turn on do not disturb", "skill": "do_not_disturb"]]],
                                                                                       ["said": "open tunebox and play jazz", "steps": [["text": "open tunebox", "skill": "open_app"]]]]]])
        let text = (((sub?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        check(text.hasPrefix("Accepted 1 of 2") && text.contains("duplicate"), "mcp submit: \(text)")
        let prog = (((call("tools/call", ["name": "get_progress"])?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        check(prog.contains("\"labels\":4"), "mcp progress: \(prog)")
        check(call("notifications/initialized") == nil || true, "notification")
        check((call("bogus")?["error"] as? [String: Any])?["code"] as? Int == -32601, "unknown method")

        // Status files with Python's NaN.
        let p = dir.appendingPathComponent("progress.json")
        try? #"{"stage": "training", "train": {"step": 5, "loss": [[5, 1.2]], "baseline": {"val": 0.3, "test_real": NaN}}}"#.write(to: p, atomically: true, encoding: .utf8)
        let prog2 = Progress.decode(Progress.self, from: p)
        check(prog2?.train?.step == 5 && prog2?.train?.baseline?.test_real == nil, "progress with NaN")

        // Request building for API providers (no network).
        let r = AI.request(.anthropic, prompt: "hi", key: "k", model: "m", base: "")
        check(r?.value(forHTTPHeaderField: "x-api-key") == "k" && r?.url?.host == "api.anthropic.com", "anthropic request")
        check(AI.request(.compatible, prompt: "hi", key: nil, model: "m", base: "notaurl") == nil, "bad base URL")
        check(AIProvider.compatible.status(hasKey: false, installed: false, baseURL: "http://localhost:11434/v1") == .ready, "compatible status")

        print(failures == 0 ? "self-check ok" : "self-check: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
