import Foundation

/// Made-up data for previews, screenshots and the "Start from the example" button. Same apps as catalogs/example.json.
@MainActor
enum Demo {
    static let catalog: Catalog = {
        var c = Catalog()
        c.context = "You are writing training data for Tars, a voice assistant on a desktop computer. Made-up apps: Tunebox (music), Inkpad (notes), a web browser, messages, a calendar and a file browser. Two screens: the laptop on the left, an external monitor on the right. Sentences are speech-to-text output: often no punctuation, sometimes misheard words."
        c.families = [
            Family(key: "time", description: "Timers, alarms and reminders: set one, check how long is left, cancel it"),
            Family(key: "calendar", description: "Calendar: what's on today or next, am I free, add or move an event"),
            Family(key: "messages", description: "Messages: send a message to someone, read new messages, call someone"),
            Family(key: "music", description: "Music playback in Tunebox: play a song, album or playlist, pause, skip, what's playing"),
            Family(key: "windows", description: "Apps and windows: open, quit or switch apps, move a window to a screen, full screen"),
            Family(key: "system", description: "Computer controls: volume, brightness, dark mode, wifi, do not disturb"),
            Family(key: "none", description: Catalog.noneDescription),
        ]
        c.skills = [
            Skill(key: "timers", family: "time", name: "Timers", examples: ["set a timer for 10 minutes", "how long's left on my timer"]),
            Skill(key: "reminders", family: "time", name: "Reminders", examples: ["remind me in an hour to call the bank"]),
            Skill(key: "am_i_free", family: "calendar", name: "Am I free", examples: ["am I free at 4", "do I have anything tomorrow at 2"]),
            Skill(key: "add_event", family: "calendar", name: "Add an event", examples: ["add lunch with Sam tomorrow at noon"]),
            Skill(key: "send_message", family: "messages", name: "Send a message", examples: ["text Sam I'm on my way"]),
            Skill(key: "call_someone", family: "messages", name: "Call someone", examples: ["call Mom", "start a video call with Alex"]),
            Skill(key: "play_music", family: "music", name: "Play music by name", examples: ["play some jazz", "put on my running playlist"]),
            Skill(key: "play_pause_skip", family: "music", name: "Play, pause, skip", examples: ["pause", "next song"]),
            Skill(key: "open_app", family: "windows", name: "Open or switch to an app", examples: ["open Tunebox", "bring up Inkpad"]),
            Skill(key: "move_window", family: "windows", name: "Move, minimize, maximize windows", examples: ["move this to the right monitor", "full screen the browser"]),
            Skill(key: "volume", family: "system", name: "Volume", examples: ["volume 40", "turn it up", "mute"]),
            Skill(key: "do_not_disturb", family: "system", name: "Do Not Disturb", examples: ["turn on do not disturb", "focus mode off"]),
        ]
        return c
    }()

    static let labels: [Labeled] = {
        let rows: [(String, [(String, String)], String)] = [
            ("open tunebox and play some jazz then move it to the right monitor", [("open tunebox", "open_app"), ("play some jazz", "play_music"), ("move it to the right monitor", "move_window")], "claude"),
            ("its way too loud", [("its way too loud", "volume")], "claude"),
            ("am i free at 4 text sam ill be late", [("am i free at 4", "am_i_free"), ("text sam ill be late", "send_message")], "claude"),
            ("set a 25 minute timer dnd on", [("set a 25 minute timer", "timers"), ("dnd on", "do_not_disturb")], "mcp"),
            ("play Stop Making Sense", [("play Stop Making Sense", "play_music")], "claude"),
            ("okay so um skip this one", [("skip this one", "play_pause_skip")], "chatgpt"),
            ("i told her the meeting moved to friday", [("i told her the meeting moved to friday", "none")], "claude"),
            ("could you remind me in an hour to water the plants", [("remind me in an hour to water the plants", "reminders")], "mcp"),
            ("call mom and pause the music", [("call mom", "call_someone"), ("pause the music", "play_pause_skip")], "claude"),
            ("put lunch with alex on thursday at noon", [("put lunch with alex on thursday at noon", "add_event")], "chatgpt"),
            ("bring up inkpad full screen it", [("bring up inkpad", "open_app"), ("full screen it", "move_window")], "claude"),
            ("turn it down a bit", [("turn it down a bit", "volume")], "mcp"),
        ]
        return rows.map { said, steps, src in Labeled(said: said, steps: steps.map { Step(text: $0.0, skill: $0.1) }, set: Labeled.defaultSet(said), source: src) }
    }()

    static func fill(_ t: Trainer) {
        func curve(_ n: Int, _ f: (Double) -> Double) -> [[Double]] { (1...n).map { s in [Double(s * 5), f(Double(s * 5))] } }
        var train = Progress.Train()
        train.step = 640; train.budget_min = 60; train.elapsed_min = 31.5; train.steps_per_sec = 0.34; train.examples = 18_400
        train.loss = curve(128) { s in 0.18 + 1.25 * exp(-s / 140) + 0.025 * sin(s / 9) }
        train.acc = curve(128) { s in min(0.97, 0.42 + 0.53 * (1 - exp(-s / 160)) + 0.012 * sin(s / 7)) }
        let base = Check(step: 0, minutes: 0, val: 0.318, val_replay: 0.931, test_style: 0.204, test_real: nil, select: 0.441)
        train.baseline = base
        train.checks = [
            Check(step: 200, minutes: 9.8, val: 0.802, val_replay: 0.925, test_style: 0.701, select: 0.827),
            Check(step: 400, minutes: 19.7, val: 0.871, val_replay: 0.927, test_style: 0.763, select: 0.882),
            Check(step: 600, minutes: 29.5, val: 0.893, val_replay: 0.926, test_style: 0.781, select: 0.900),
        ]
        train.best = train.checks?.last
        t.progress = Progress(stage: "training", message: "Full fine-tune", log: [
            "10:02:11  — building: Split, route and skill questions", "10:03:40  — evaluating: Baseline on the test sets",
            "10:05:02  — training: Full fine-tune", "10:34:31  step 600: val 89.3%  replay 92.6%", "10:34:32    -> best so far (step 600), saved",
        ], train: train, eval: nil, started: Date().timeIntervalSince1970 - 1900)
        t.running = true
        t.report = EvalReport(
            base: ["test_hard": ["split": 41.2, "route": 38.5, "skill": 80.1, "all": 52.0, "sentence": 6.3, "ms_per_question": 21.4],
                   "val_replay": ["general": 93.1, "all": 93.1]],
            candidate: ["test_hard": ["split": 96.4, "route": 88.7, "skill": 93.0, "all": 92.6, "sentence": 71.9, "ms_per_question": 21.6],
                        "val_replay": ["general": 92.6, "all": 92.6]],
            verdict: "PROMOTE", reasons: ["hard multi-step 6.3% → 71.9%"])
        let runEval = t.report
        t.runs = [
            PastRun(id: "20261114-213005", baseline: base, best: Check(step: 1200, minutes: 58, val: 0.912, val_replay: 0.924, test_style: 0.79), history: [], eval: runEval),
            PastRun(id: "20261112-180210", baseline: base, best: Check(step: 800, minutes: 40, val: 0.861, val_replay: 0.929, test_style: 0.74), history: [], eval: nil),
            PastRun(id: "20261110-091544", baseline: base, best: Check(step: 4, minutes: 2, val: 0.355, val_replay: 0.930, test_style: 0.22), history: [], eval: nil),
        ]
        t.tryResult = [
            "base": Decision(steps: [Decision.DStep(text: "open tunebox and play some jazz", family: "windows", family_p: 0.41, skill: "open_app", skill_p: 0.62)], ms: 188),
            "candidate": Decision(steps: [Decision.DStep(text: "open tunebox", family: "windows", family_p: 0.99, skill: "open_app", skill_p: 0.98),
                                          Decision.DStep(text: "play some jazz", family: "music", family_p: 1.0, skill: "play_music", skill_p: 0.99)], ms: 204),
        ]
        t.logTail = "[10:34:31] step 600: val 89.3%  replay 92.6%  |  test_style 78.1%  test_real nan%  (41s)\n[10:34:32]   -> best so far (step 600), saved"
    }
}
