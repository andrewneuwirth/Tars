import Foundation

/// Where the Python side lives. The app runs the repository's own pipeline (pipeline/run.sh with LABELS=), so training,
/// evaluation and the promote/keep verdict are exactly what the command line does.
enum Setup {
    /// Advanced: train with your own checkout, Python and Von instead of the environment the app sets up.
    static var useOwn: Bool {
        get { UserDefaults.standard.bool(forKey: "useOwnEnvironment") }
        set { UserDefaults.standard.set(newValue, forKey: "useOwnEnvironment") }
    }
    static var ownRepo: String {
        get { UserDefaults.standard.string(forKey: "repoPath") ?? Bundled.checkout?.path ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "repoPath") }
    }
    static var ownPython: String {
        get { UserDefaults.standard.string(forKey: "pythonPath") ?? (ownRepo.isEmpty ? "" : ownRepo + "/.venv/bin/python") }
        set { UserDefaults.standard.set(newValue, forKey: "pythonPath") }
    }
    static var ownVon: String {
        get { UserDefaults.standard.string(forKey: "vonPath") ?? (ownRepo.isEmpty ? "" : (ownRepo as NSString).deletingLastPathComponent + "/von") }
        set { UserDefaults.standard.set(newValue, forKey: "vonPath") }
    }

    static var repo: String { useOwn ? ownRepo : Bundled.training?.path ?? "" }
    static var python: String { useOwn ? ownPython : Files.env.appendingPathComponent("venv/bin/python").path }
    static var von: String { useOwn ? ownVon : Files.von.path }
    static var base: String { useOwn ? ownVon + "/checkpoints/von-1.2" : Files.baseModel.path }

    static var minutes: Double {
        get { let m = UserDefaults.standard.double(forKey: "trainMinutes"); return m > 0 ? m : 60 }
        set { UserDefaults.standard.set(newValue, forKey: "trainMinutes") }
    }
    static var target: Int {
        get { let t = UserDefaults.standard.integer(forKey: "labelTarget"); return t > 0 ? t : 2000 }
        set { UserDefaults.standard.set(newValue, forKey: "labelTarget") }
    }
    /// Start training from the published Tars model instead of Von 1.2 (when it has been downloaded).
    static var startFromTars: Bool {
        get { UserDefaults.standard.bool(forKey: "startFromTars") }
        set { UserDefaults.standard.set(newValue, forKey: "startFromTars") }
    }

    /// What's missing before a run can start, in words.
    static func problems() -> [String] {
        guard useOwn else { return Installer.ready ? [] : ["Set up training first (one time, downloads \(Installer.downloadSize))."] }
        let fm = FileManager.default
        var out: [String] = []
        if !fm.fileExists(atPath: repo + "/pipeline/run.sh") { out.append("Choose the Tars folder (the checkout with pipeline/run.sh).") }
        if !fm.isExecutableFile(atPath: python) { out.append("Python not found at \(python).") }
        if !fm.fileExists(atPath: von + "/src") { out.append("Von not found at \(von). Clone github.com/wfzyx/von there.") }
        if !fm.fileExists(atPath: base + "/option_marker.pt") { out.append("Von 1.2 weights not found in \(base).") }
        return out
    }

    /// The environment every Python run gets: where Von and the models are, and no network for Hugging Face.
    static var pythonEnv: [String: String] {
        ["VON_REPO": von, "TARS_BASE": base, "PYTHONDONTWRITEBYTECODE": "1", "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1",
         "TARS_CHECKPOINT": Files.checkpoint.path]
    }
}

// MARK: The live status pipeline/status.py writes

struct Check: Codable, Hashable {
    var step: Int?
    var minutes: Double?
    var val: Double?
    var val_replay: Double?
    var test_style: Double?
    var test_real: Double?
    var select: Double?
}

struct Progress: Codable {
    struct Train: Codable {
        var step: Int?
        var steps_per_sec: Double?
        var elapsed_min: Double?
        var budget_min: Double?
        var examples: Int?
        var loss: [[Double]]?
        var acc: [[Double]]?
        var checks: [Check]?
        var baseline: Check?
        var best: Check?
        var stop_reason: String?
    }
    struct Eval: Codable { var verdict: String?; var reasons: [String]? }
    var stage: String?
    var message: String?
    var log: [String]?
    var train: Train?
    var eval: Eval?
    var started: Double?

    /// Python's json writes NaN for an empty test set; JSON has no NaN.
    static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let clean = text.replacingOccurrences(of: #"\b(NaN|-?Infinity)\b"#, with: "null", options: .regularExpression)
        return try? JSONDecoder().decode(T.self, from: Data(clean.utf8))
    }
}

/// data/eval_report.json: per model, per test set, accuracy per question kind (split, route, skill, general) and per sentence.
struct EvalReport: Codable {
    var base: [String: [String: Double]]?
    var candidate: [String: [String: Double]]?
    var verdict: String?
    var reasons: [String]?

    /// The test set the comparison shows: the user's own sentences, else held-out labels.
    var mainSet: String? { ["test_real", "test_hard", "test_style"].first { candidate?[$0] != nil && base?[$0] != nil } }
}

/// One finished run in runs/<date>/: train.py's progress.json, plus the eval report the app files next to it.
struct PastRun: Identifiable {
    var id: String          // folder name, e.g. 20261115-101500
    var baseline: Check?
    var best: Check?
    var history: [Check]
    var eval: EvalReport?
    var date: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.date(from: id)
    }

    static func all(in dir: URL = Files.runs) -> [PastRun] {
        struct File: Codable { var baseline: Check?; var history: [Check]?; var best: Check? }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted(by: >).compactMap { name in
            let d = dir.appendingPathComponent(name)
            guard let f = Progress.decode(File.self, from: d.appendingPathComponent("progress.json")) else { return nil }
            return PastRun(id: name, baseline: f.baseline, best: f.best, history: f.history ?? [], eval: Progress.decode(EvalReport.self, from: d.appendingPathComponent("eval.json")))
        }
    }
}

/// What try.py said each model decided for one sentence.
struct Decision: Codable, Hashable {
    struct DStep: Codable, Hashable { var text: String; var family: String?; var family_p: Double?; var skill: String?; var skill_p: Double? }
    var steps: [DStep]?
    var ms: Double?
    var error: String?
}

@MainActor @Observable
final class Trainer {
    var progress = Progress()
    var report: EvalReport?
    var runs: [PastRun] = []
    var logTail = ""
    var running = false
    var quick = false
    var exitStatus: Int32?
    var tryResult: [String: Decision] = [:]
    var trying = false
    var tryError: String?
    private var process: Process?
    private var poll: Timer?

    func refresh() {
        if let p = Progress.decode(Progress.self, from: Files.progress) { progress = p }
        report = Progress.decode(EvalReport.self, from: Files.data.appendingPathComponent("eval_report.json"))
        runs = PastRun.all()
        if let t = try? String(contentsOf: Files.log, encoding: .utf8) { logTail = String(t.suffix(6000)) }
    }

    /// pipeline/run.sh with this app's catalog and labels. Quick mode: a handful of steps, to prove the setup works.
    func start(catalog: URL = Files.catalog, labels: URL = Files.labels) {
        guard !running else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: Files.stop)
        try? fm.removeItem(at: Files.progress)
        try? fm.createDirectory(at: Files.runs, withIntermediateDirectories: true)
        try? fm.createDirectory(at: Files.checkpoint.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: Files.log.path, contents: nil)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["pipeline/run.sh"]
        p.currentDirectoryURL = URL(fileURLWithPath: Setup.repo)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        env.merge(Setup.pythonEnv) { $1 }
        env.merge([
            "PYTHON": Setup.python, "CATALOG": catalog.path, "LABELS": labels.path,
            "TARS_DATA": Files.data.path, "TARS_PROGRESS": Files.progress.path, "TARS_RUNS": Files.runs.path,
            "RUN_LOG": Files.log.path,
            "MINUTES": quick ? "3" : String(Int(Setup.minutes)),
        ]) { $1 }
        var flags: [String] = []
        if Setup.startFromTars, FileManager.default.fileExists(atPath: Files.tarsModel.appendingPathComponent("option_marker.pt").path) {
            flags += ["--init", Files.tarsModel.path]   // shortcut: a path with spaces would split here (run.sh splits TRAIN_FLAGS); Application Support has none
        }
        if quick {
            flags += ["--max-steps", "4", "--eval-every", "2"]
            env["BUILD_FLAGS"] = "--general 60"
            env["BATCH"] = "4"; env["ACCUM"] = "1"
        }
        if !flags.isEmpty { env["TRAIN_FLAGS"] = flags.joined(separator: " ") }
        p.environment = env
        p.standardOutput = FileHandle.nullDevice   // run.sh tees everything into RUN_LOG
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { proc in
            Task { @MainActor in self.finished(proc.terminationStatus) }
        }
        do { try p.run() } catch { logTail = "Couldn't start the pipeline: \(error.localizedDescription)"; return }
        process = p
        running = true
        exitStatus = nil
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in Task { @MainActor in self.refresh() } }
    }

    /// Asks train.py to stop at its next step (it saves the best checkpoint so far), then the evaluation still runs.
    func stop() { FileManager.default.createFile(atPath: Files.stop.path, contents: nil) }
    func cancel() { process?.interrupt() }

    private func finished(_ status: Int32) {
        poll?.invalidate()
        running = false
        exitStatus = status
        refresh()
        // File the verdict with the run it belongs to, so past runs keep their scores.
        if let newest = runs.first {
            let dest = Files.runs.appendingPathComponent(newest.id).appendingPathComponent("eval.json")
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: Files.data.appendingPathComponent("eval_report.json"), to: dest)
            runs = PastRun.all()
        }
    }

    /// Copies the candidate checkpoint, with the catalog it was trained for, into `folder`.
    func export(to folder: URL, catalog: Catalog) throws {
        let dest = folder.appendingPathComponent("tars-model")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: Files.candidate, to: dest)
        Files.save(catalog, to: dest.appendingPathComponent("catalog.json"))
    }

    var hasCandidate: Bool { FileManager.default.fileExists(atPath: Files.candidate.appendingPathComponent("option_marker.pt").path) }

    /// Plans one sentence with the base model and the fine-tuned one (pipeline/try.py).
    func tryCommand(_ said: String) {
        guard !trying, !said.isEmpty else { return }
        trying = true
        tryError = nil
        let env = Setup.pythonEnv
        let args = [Setup.repo + "/pipeline/try.py", "--catalog", Files.catalog.path, said, "base", "candidate"]
        let python = Setup.python
        Task {
            do {
                let out = try await Self.run(python, args, env: env)
                // The JSON is the last line; model loading may print warnings before it.
                let last = out.split(separator: "\n").last.map(String.init) ?? ""
                if let d = try? JSONDecoder().decode([String: Decision].self, from: Data(last.utf8)) {
                    tryResult = d
                } else { tryError = String(out.suffix(400)) }
            } catch { tryError = error.localizedDescription }
            trying = false
        }
    }

    nonisolated static func run(_ exe: String, _ args: [String], env extra: [String: String]) async throws -> String {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            p.environment = ProcessInfo.processInfo.environment.merging(extra) { $1 }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("tars-try-\(UUID().uuidString).txt")
            FileManager.default.createFile(atPath: out.path, contents: nil)
            defer { try? FileManager.default.removeItem(at: out) }
            p.standardOutput = try FileHandle(forWritingTo: out)
            p.standardError = p.standardOutput
            try p.run()
            p.waitUntilExit()
            let text = (try? String(contentsOf: out, encoding: .utf8)) ?? ""
            guard p.terminationStatus == 0 else { throw AIFailure(String(text.suffix(400))) }
            return text
        }.value
    }
}
