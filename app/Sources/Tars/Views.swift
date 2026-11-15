import SwiftUI
import MacToolsKit

enum Section: String, CaseIterable, Identifiable {
    case catalog = "Catalog", labels = "Labels", generate = "Make Labels", train = "Train", lab = "Model Lab", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .catalog: "square.grid.2x2"
        case .labels: "tablecells"
        case .generate: "sparkles"
        case .train: "play.circle"
        case .lab: "chart.xyaxis.line"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Bindable var app: AppModel
    @State var section: Section = .catalog
    @AppStorage("onboarded") private var onboarded = false
    var showOnboarding = true
    /// Offscreen rendering can't draw the system sidebar material, so previews draw a plain one.
    var plainSidebar = false

    var body: some View {
        if plainSidebar {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Section.allCases) { s in
                        HStack {
                            Label(s.rawValue, systemImage: s.symbol)
                            Spacer()
                            if s == .labels { Text("\(app.labels.count)").foregroundStyle(Color.mtInkMuted) }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: MT.Radius.control).fill(s == section ? Color.mtFillHover : .clear))
                    }
                    Spacer()
                }
                .padding(.top, 40).padding(.horizontal, 10)
                .frame(width: 200).frame(maxHeight: .infinity)
                .background(Color.mtSurface)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.mtGround)
            }
        } else {
            split
        }
    }

    private var split: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
                    .badge(s == .labels ? Text("\(app.labels.count)") : nil)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            detail
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.mtGround)
        }
        .sheet(isPresented: Binding(get: { showOnboarding && !onboarded && !app.demo }, set: { if !$0 { onboarded = true } })) {
            OnboardingView(app: app) { onboarded = true }
        }
    }
}

extension RootView {
    @ViewBuilder var detail: some View {
        switch section {
        case .catalog: CatalogView(app: app)
        case .labels: LabelsView(app: app)
        case .generate: GenerateView(app: app)
        case .train: TrainView(app: app, trainer: app.trainer)
        case .lab: ModelLabView(app: app, trainer: app.trainer)
        case .settings: SettingsView(app: app)
        }
    }
}

// MARK: Shared pieces

struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MT.Space.s18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 22, weight: .semibold))
                    Text(subtitle).foregroundStyle(Color.mtInkMuted)
                }
                content
            }
            .padding(MT.Space.s26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: MT.Space.s10) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding(MT.Space.s18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MT.Radius.card).fill(Color.mtSurface))
        .overlay(RoundedRectangle(cornerRadius: MT.Radius.card).strokeBorder(Color.mtHairline))
    }
}

struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Color.mtInkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Problems: View {
    let items: [String]
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { p in
                    Label(p, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.mtWarn).font(.callout)
                }
            }
        }
    }
}

func pct(_ v: Double?) -> String { v.map { String(format: "%.1f%%", $0 * 100) } ?? "–" }

// MARK: Catalog

struct CatalogView: View {
    @Bindable var app: AppModel
    @State private var selected: String?

    var body: some View {
        Page(title: "Catalog", subtitle: "The tools and skills your assistant has. Tars learns to pick between them.") {
            Problems(items: app.catalog.problems)
            Card(title: "Assistant") {
                TextField("Name", text: $app.catalog.assistant).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Text("Context for the AI that writes labels: what device, which apps, how people talk to it.").font(.caption).foregroundStyle(Color.mtInkMuted)
                TextEditor(text: $app.catalog.context).font(.body).frame(minHeight: 70).scrollContentBackground(.hidden)
                    .padding(6).background(RoundedRectangle(cornerRadius: MT.Radius.control).fill(Color.mtFillInset))
            }
            Card(title: "Families") {
                Text("The first decision: which part of the assistant handles a request. Keep \"none\" for things that aren't requests.")
                    .font(.caption).foregroundStyle(Color.mtInkMuted)
                ForEach($app.catalog.families) { $f in
                    HStack {
                        Text(f.key).font(.body.monospaced()).frame(width: 110, alignment: .leading)
                        TextField("What belongs here", text: $f.description).textFieldStyle(.roundedBorder)
                        Button { app.catalog.families.removeAll { $0.key == f.key } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).disabled(f.key == "none").accessibilityLabel("Remove \(f.key)")
                    }
                }
                AddFamily { key in app.catalog.families.insert(Family(key: key, description: ""), at: max(0, app.catalog.families.count - 1)) }
            }
            Card(title: "Skills") {
                Text("The second decision: which skill in that family. A few examples each, in the words people actually use.")
                    .font(.caption).foregroundStyle(Color.mtInkMuted)
                ForEach($app.catalog.skills) { $s in SkillRow(skill: $s, families: app.catalog.families.map(\.key).filter { $0 != "none" }, count: app.skillCounts[s.key] ?? 0) {
                    app.catalog.skills.removeAll { $0.key == s.key }
                } }
                Button {
                    let fam = app.catalog.families.first { $0.key != "none" }?.key ?? "none"
                    var n = 1
                    while app.catalog.skills.contains(where: { $0.key == "new_skill_\(n)" }) { n += 1 }
                    app.catalog.skills.append(Skill(key: "new_skill_\(n)", family: fam, name: "New skill", examples: []))
                } label: { Label("Add Skill", systemImage: "plus") }
                .disabled(app.catalog.families.count < 2)
            }
        }
    }
}

struct AddFamily: View {
    let add: (String) -> Void
    @State private var name = ""
    var body: some View {
        HStack {
            TextField("New family key, e.g. music", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 240).onSubmit(go)
            Button("Add Family", action: go).disabled(Catalog.key(name).isEmpty)
        }
    }
    private func go() { let k = Catalog.key(name); guard !k.isEmpty else { return }; add(k); name = "" }
}

struct SkillRow: View {
    @Binding var skill: Skill
    let families: [String]
    let count: Int
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Name", text: $skill.name).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                TextField("key", text: $skill.key).textFieldStyle(.roundedBorder).font(.body.monospaced()).frame(maxWidth: 170)
                Picker("", selection: $skill.family) { ForEach(families, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 120)
                Spacer()
                Text("\(count) labels").font(.caption).foregroundStyle(Color.mtInkMuted).monospacedDigit()
                Button(action: remove) { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("Delete \(skill.name)")
            }
            TextField("Examples, separated by ;", text: Binding(get: { skill.examples.joined(separator: "; ") },
                                                                set: { skill.examples = $0.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                .textFieldStyle(.roundedBorder).foregroundStyle(Color.mtInkMuted)
        }
        .padding(.vertical, 4)
    }
}

// MARK: Labels

struct LabelsView: View {
    @Bindable var app: AppModel
    @State private var selection = Set<UUID>()
    @State private var search = ""
    @State private var skillFilter = "all"
    @State private var editing: Labeled?
    @State private var sample: [UUID]?

    private var shown: [Labeled] {
        let base = sample.map { ids in app.labels.filter { ids.contains($0.id) } } ?? app.labels
        return base.filter { l in
            (search.isEmpty || l.said.localizedCaseInsensitiveContains(search))
                && (skillFilter == "all" || (skillFilter == "invalid" ? l.problem(in: app.catalog) != nil : l.steps.contains { $0.skill == skillFilter }))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: MT.Space.s12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Labels").font(.system(size: 22, weight: .semibold))
                    Text("\(app.labels.count) sentences · \(app.labels.filter { $0.set == "test" }.count) held out for testing · \(app.invalid.count) need fixing")
                        .foregroundStyle(Color.mtInkMuted)
                }
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
                Picker("Skill", selection: $skillFilter) {
                    Text("All skills").tag("all")
                    Text("Need fixing").tag("invalid")
                    Divider()
                    ForEach(app.catalog.skills) { Text($0.name).tag($0.key) }
                    Text("none").tag("none")
                }.frame(width: 190)
                Button(sample == nil ? "Spot-Check 20" : "Show All") {
                    sample = sample == nil ? Array(app.labels.shuffled().prefix(20).map(\.id)) : nil
                }
                Button(role: .destructive) { app.delete(selection); selection = [] } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selection.isEmpty)
            }
            .padding(MT.Space.s18)
            Table(shown, selection: $selection) {
                TableColumn("Said") { l in
                    HStack(spacing: 6) {
                        if l.problem(in: app.catalog) != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.mtWarn) }
                        Text(l.said).lineLimit(2)
                    }
                }
                TableColumn("Steps") { l in Text(l.steps.map { "\($0.text) → \($0.skill)" }.joined(separator: "\n")).foregroundStyle(Color.mtInkMuted).lineLimit(4) }
                TableColumn("Set") { l in Text(l.set) }.width(50)
                TableColumn("From") { l in Text(l.source) }.width(70)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                Button("Edit") { editing = app.labels.first { ids.contains($0.id) } }.disabled(ids.count != 1)
                Button("Move to Test") { for id in ids { if var l = app.labels.first(where: { $0.id == id }) { l.set = "test"; app.update(l) } } }
                Button("Move to Train") { for id in ids { if var l = app.labels.first(where: { $0.id == id }) { l.set = "train"; app.update(l) } } }
                Divider()
                Button("Delete", role: .destructive) { app.delete(ids) }
            } primaryAction: { ids in editing = app.labels.first { ids.contains($0.id) } }
            .onDeleteCommand { app.delete(selection); selection = [] }
        }
        .sheet(item: $editing) { l in LabelEditor(label: l, catalog: app.catalog) { app.update($0) } }
    }
}

struct LabelEditor: View {
    @State var label: Labeled
    let catalog: Catalog
    let save: (Labeled) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: MT.Space.s12) {
            Text("Edit Label").font(.headline)
            TextField("Said", text: $label.said).textFieldStyle(.roundedBorder)
            ForEach(label.steps.indices, id: \.self) { i in
                HStack {
                    TextField("Step text", text: $label.steps[i].text).textFieldStyle(.roundedBorder)
                    Picker("", selection: $label.steps[i].skill) {
                        ForEach(catalog.skills) { Text($0.name).tag($0.key) }
                        Text("none").tag("none")
                    }.labelsHidden().frame(width: 200)
                    Button { label.steps.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).disabled(label.steps.count == 1)
                }
            }
            Button { label.steps.append(Step(text: "", skill: catalog.skills.first?.key ?? "none")) } label: { Label("Add Step", systemImage: "plus") }
            Picker("Set", selection: $label.set) { Text("Train").tag("train"); Text("Test").tag("test"); Text("Real").tag("real") }.pickerStyle(.segmented).frame(width: 240)
            if let p = label.problem(in: catalog) { Problems(items: [p]) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(label); dismiss() }.keyboardShortcut(.defaultAction).disabled(label.problem(in: catalog) != nil)
            }
        }
        .padding(MT.Space.s26)
        .frame(width: 620)
    }
}

// MARK: Making labels

struct GenerateView: View {
    @Bindable var app: AppModel
    @State private var provider = AISettings.provider
    @State private var target = Setup.target

    var body: some View {
        let gen = app.generator
        Page(title: "Make Labels", subtitle: "Labels are example commands with the right steps and skills. A good model needs thousands; Tars 0.4 was trained on about 10,000.") {
            Problems(items: app.catalog.problems)
            Card(title: "With your AI provider") {
                HStack {
                    Picker("Provider", selection: $provider) { ForEach(AIProvider.allCases) { Text($0.title).tag($0) } }
                        .frame(maxWidth: 360)
                        .onChange(of: provider) { AISettings.provider = provider }
                    let st = provider.status
                    Label(st.title, systemImage: st == .ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(st == .ready ? Color.mtGood : Color.mtWarn)
                }
                HStack {
                    Text("Target")
                    TextField("", value: $target, format: .number).textFieldStyle(.roundedBorder).frame(width: 90)
                        .onChange(of: target) { Setup.target = max(1, target) }
                    Text("labels").foregroundStyle(Color.mtInkMuted)
                }
                ProgressView(value: Double(min(app.labels.count, target)), total: Double(max(target, 1))) {
                    Text("\(app.labels.count) of \(target)").monospacedDigit()
                }
                HStack {
                    if gen.running {
                        Button("Stop") { gen.stop() }
                        ProgressView().controlSize(.small)
                        Text("\(gen.asked) requests, \(gen.failed) failed").foregroundStyle(Color.mtInkMuted)
                    } else {
                        Button("Start Making Labels") { gen.start(app, target: target) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!app.catalog.problems.isEmpty || provider.status != .ready || app.demo)
                    }
                }
                if let e = gen.lastError { Label(e, systemImage: "xmark.octagon").foregroundStyle(Color.mtBad).font(.callout).textSelection(.enabled) }
                if !gen.lastRejected.isEmpty {
                    DisclosureGroup("\(gen.lastRejected.count) rejected in the last batch") {
                        Text(gen.lastRejected.prefix(12).joined(separator: "\n")).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                Text("Your catalog and the prompts go to the provider you pick. Subscriptions run their own command line tool on this Mac; API keys stay in your Keychain.")
                    .font(.caption).foregroundStyle(Color.mtInkMuted)
            }
            Card(title: "With any agent (MCP)") {
                Text("Tars runs an MCP server so Claude Code, Codex or any MCP client can write labels. They get your catalog and the label rules, and every label they send is checked before it's kept.")
                    .foregroundStyle(Color.mtInkMuted)
                let cmd = "claude mcp add tars -- \(Bundle.main.executablePath ?? "/Applications/Tars.app/Contents/MacOS/Tars") --mcp"
                HStack {
                    Text(cmd).font(.callout.monospaced()).textSelection(.enabled).lineLimit(2)
                    Spacer()
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cmd, forType: .string) }
                }
                .padding(10).background(RoundedRectangle(cornerRadius: MT.Radius.control).fill(Color.mtFillInset))
                Text("Then ask it: \"Use the tars tools to write 500 labels, thinnest skills first.\" Tools: get_catalog, get_label_schema, submit_labels, get_progress.")
                    .font(.caption).foregroundStyle(Color.mtInkMuted)
            }
            Card(title: "Coverage") {
                let counts = app.skillCounts
                let most = max(1, counts.values.max() ?? 1)
                ForEach(app.catalog.skills + [Skill(key: "none", family: "none", name: "Not a request", examples: [])]) { s in
                    HStack {
                        Text(s.name).frame(width: 220, alignment: .leading).lineLimit(1)
                        GeometryReader { g in
                            Capsule().fill(Color.mtRingTrack)
                                .overlay(alignment: .leading) { Capsule().fill(Color.accentColor).frame(width: g.size.width * CGFloat(counts[s.key] ?? 0) / CGFloat(most)) }
                        }.frame(height: 6)
                        Text("\(counts[s.key] ?? 0)").monospacedDigit().frame(width: 50, alignment: .trailing).foregroundStyle(Color.mtInkMuted)
                    }
                }
            }
        }
    }
}

// MARK: Training

struct TrainView: View {
    @Bindable var app: AppModel
    @Bindable var trainer: Trainer
    @State private var minutes = Setup.minutes
    @State private var exportError: String?

    var body: some View {
        let problems = app.demo ? [] : Setup.problems() + app.catalog.problems
        Page(title: "Train", subtitle: "Fine-tunes the base model on your labels with the repository's pipeline: build, baseline, train, compare.") {
            if !Setup.useOwn && (!Installer.ready || app.installer.state == .running) && !app.demo { SetupCard(installer: app.installer) }
            Problems(items: problems.filter { !$0.hasPrefix("Set up training") })
            if app.labels.count < 300 { Problems(items: ["Only \(app.labels.count) labels. A few thousand give a much better model."]) }
            Card(title: "Run") {
                HStack {
                    Text("Time budget")
                    Slider(value: $minutes, in: 10...240, step: 10).frame(width: 220).onChange(of: minutes) { Setup.minutes = minutes }
                    Text("\(Int(minutes)) min").monospacedDigit()
                }
                Toggle("Quick test run (a few steps, to check the setup works)", isOn: $trainer.quick)
                HStack {
                    if trainer.running {
                        Button("Stop and Keep Best") { trainer.stop() }
                        Button("Cancel", role: .destructive) { trainer.cancel() }
                    } else {
                        Button("Start Training") { trainer.start() }.buttonStyle(.borderedProminent).disabled(!problems.isEmpty || app.labels.isEmpty)
                    }
                    if let s = trainer.exitStatus { Text(s == 0 ? "Finished" : "Stopped (exit \(s))").foregroundStyle(s == 0 ? Color.mtGood : Color.mtBad) }
                }
            }
            StageCard(progress: trainer.progress)
            if let r = trainer.report, let v = r.verdict {
                Card(title: "Verdict") {
                    Label(v == "PROMOTE" ? "Better than the base model" : "Not better yet", systemImage: v == "PROMOTE" ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(v == "PROMOTE" ? Color.mtGood : Color.mtWarn).font(.headline)
                    Text((r.reasons ?? []).joined(separator: " · ")).foregroundStyle(Color.mtInkMuted)
                }
            }
            Card(title: "Export") {
                Text("Copies the fine-tuned checkpoint and your catalog into a folder. Load it with Planner(Catalog.load(\"catalog.json\"), \"tars-model\").")
                    .font(.caption).foregroundStyle(Color.mtInkMuted)
                Button("Export Model…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Export Here"
                    if panel.runModal() == .OK, let u = panel.url {
                        do { try trainer.export(to: u, catalog: app.catalog); exportError = nil } catch { exportError = error.localizedDescription }
                    }
                }.disabled(!trainer.hasCandidate)
                if let exportError { Text(exportError).foregroundStyle(Color.mtBad) }
            }
            Card(title: "Log") {
                Text(trainer.logTail.isEmpty ? "Nothing yet." : trainer.logTail).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct StageCard: View {
    let progress: Progress
    static let stages = ["building", "evaluating", "training", "done"]
    var body: some View {
        Card(title: "Progress") {
            HStack(spacing: 8) {
                ForEach(Self.stages, id: \.self) { s in
                    let now = progress.stage ?? ""
                    let idx = Self.stages.firstIndex(of: now) ?? -1, mine = Self.stages.firstIndex(of: s)!
                    Label(s.capitalized, systemImage: mine < idx || now == "done" ? "checkmark.circle.fill" : mine == idx ? "circle.dotted" : "circle")
                        .foregroundStyle(mine <= idx ? Color.mtInk : Color.mtInkMuted)
                    if s != "done" { Rectangle().fill(Color.mtHairline).frame(height: 1) }
                }
            }
            if let t = progress.train, let step = t.step {
                HStack {
                    Stat(value: "\(step)", label: "steps")
                    Stat(value: String(format: "%.0f / %.0f min", t.elapsed_min ?? 0, t.budget_min ?? 0), label: "time")
                    Stat(value: pct(t.best?.val), label: "best validation")
                    Stat(value: pct(t.baseline?.val), label: "base model")
                }
            }
            if let m = progress.message, !m.isEmpty { Text(m).foregroundStyle(Color.mtInkMuted) }
        }
    }
}
