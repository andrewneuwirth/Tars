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

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(app: app, section: $section)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Look.canvas)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18).strokeBorder(Look.line))
                .padding(.vertical, 8)
        }
        .background(Look.canvas)
        .ignoresSafeArea()
        .tint(Look.ink)
        .sheet(isPresented: Binding(get: { showOnboarding && !onboarded && !app.demo }, set: { if !$0 { onboarded = true } })) {
            OnboardingView(app: app) { onboarded = true }
        }
    }

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

// MARK: Sidebar

struct Sidebar: View {
    @Bindable var app: AppModel
    @Binding var section: Section
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: 34)   // the traffic lights
            HStack(spacing: 10) {
                Image(nsImage: AppIcon.image).resizable().interpolation(.high).frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tars").font(.ui(16, .semibold))
                    Text(subtitle).font(.ui(11.5)).foregroundStyle(Look.muted).lineLimit(1)
                }
            }
            .padding(.leading, 6).padding(.bottom, 18)
            .accessibilityElement(children: .combine)
            ForEach(Section.allCases.filter { $0 != .settings }) { s in row(s) }
            Spacer()
            row(.settings).padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
        .frame(width: 214)
        .frame(maxHeight: .infinity)
    }

    private var subtitle: String {
        app.trainer.hasCandidate ? "Your model is ready" : "Version \(Self.version)"
    }

    private func row(_ s: Section) -> some View {
        let on = section == s
        return Button { section = s } label: {
            HStack(spacing: 11) {
                Image(systemName: s.symbol).font(.ui(14, .medium)).frame(width: 20)
                Text(s.rawValue).font(.ui(13.5, on ? .semibold : .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if s == .labels { count(app.labels.count, on) }
                if s == .catalog { count(app.catalog.skills.count, on) }
                if s == .train && app.trainer.running { Pulse() }
                if s == .generate && app.generator.running { Pulse() }
            }
            .foregroundStyle(on ? Look.ink : Look.muted)
            .padding(.horizontal, 11).frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11).fill(on ? Look.card : .clear)
                .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 3, y: 1))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(on ? Look.line : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func count(_ n: Int, _ on: Bool) -> some View {
        Text(n.formatted()).font(.ui(11.5, .medium)).monospacedDigit()
            .foregroundStyle(on ? Look.ink : Look.muted)
            .padding(.horizontal, 7).frame(minHeight: 19)
            .background(Capsule().fill(on ? Look.pill : Look.line))
    }
}

// MARK: Shared pieces

/// A screen: a header bar (title, subtitle, actions) above a scrolling column of cards.
struct Page<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: title, subtitle: subtitle) { actions }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.horizontal, 28).padding(.vertical, 22)
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension Page where Actions == EmptyView {
    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, actions: { EmptyView() }, content: content)
    }
}

struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.ui(22, .semibold)).accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(.ui(13)).foregroundStyle(Look.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                actions.fixedSize()
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 16)
            Rectangle().fill(Look.line).frame(height: 1)
        }
        .background(Look.panel)
    }
}

struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.ui(20, .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.ui(12)).foregroundStyle(Look.muted).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Look.field))
    }
}

struct Problems: View {
    let items: [String]
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) { ForEach(items, id: \.self) { Notice(text: $0) } }
        }
    }
}

func pct(_ v: Double?) -> String { v.map { String(format: "%.1f%%", $0 * 100) } ?? "–" }

// MARK: Catalog

struct CatalogView: View {
    @Bindable var app: AppModel

    var body: some View {
        Page(title: "Catalog", subtitle: "The tools and skills your assistant has. Tars learns to pick between them.") {
            Problems(items: app.catalog.problems)
            Card(title: "Assistant", detail: "Context for the AI that writes labels: what device, which apps, how people talk to it.") {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Name")
                    DField(placeholder: "Name", text: $app.catalog.assistant, width: 260)
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Context")
                    DEditor(placeholder: "Describe the device, the apps and how people talk to it", text: $app.catalog.context, minHeight: 84)
                }
            }
            Card(title: "Families", detail: "The first decision: which part of the assistant handles a request. Keep \"none\" for things that aren't requests.") {
                VStack(spacing: 8) {
                    ForEach($app.catalog.families) { $f in
                        HStack(spacing: 10) {
                            Tag(text: f.key, mono: true).frame(width: 110, alignment: .leading)
                            DField(placeholder: "What belongs here", text: $f.description)
                            IconButton(symbol: "minus.circle", label: "Remove \(f.key)") { app.catalog.families.removeAll { $0.key == f.key } }
                                .disabled(f.key == "none")
                        }
                    }
                }
                AddFamily { key in app.catalog.families.insert(Family(key: key, description: ""), at: max(0, app.catalog.families.count - 1)) }
            }
            Card(title: "Skills", detail: "The second decision: which skill in that family. A few examples each, in the words people actually use.") {
                VStack(spacing: 10) {
                    ForEach($app.catalog.skills) { $s in
                        SkillRow(skill: $s, families: app.catalog.families.map(\.key).filter { $0 != "none" }, count: app.skillCounts[s.key] ?? 0) {
                            app.catalog.skills.removeAll { $0.key == s.key }
                        }
                    }
                }
                Button {
                    let fam = app.catalog.families.first { $0.key != "none" }?.key ?? "none"
                    var n = 1
                    while app.catalog.skills.contains(where: { $0.key == "new_skill_\(n)" }) { n += 1 }
                    app.catalog.skills.append(Skill(key: "new_skill_\(n)", family: fam, name: "New skill", examples: []))
                } label: { Label("Add Skill", systemImage: "plus") }
                .buttonStyle(DButton())
                .disabled(app.catalog.families.count < 2)
            }
        }
    }
}

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.ui(12, .medium)).foregroundStyle(Look.muted) }
}

struct AddFamily: View {
    let add: (String) -> Void
    @State private var name = ""
    var body: some View {
        HStack(spacing: 8) {
            DField(placeholder: "New family key, e.g. music", text: $name, width: 260, onSubmit: go)
            Button(action: go) { Label("Add Family", systemImage: "plus") }.buttonStyle(DButton()).disabled(Catalog.key(name).isEmpty)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DField(placeholder: "Name", text: $skill.name).frame(maxWidth: 240)
                DField(placeholder: "key", text: $skill.key, mono: true).frame(maxWidth: 180)
                DMenu(label: "Family", selection: $skill.family, options: families.map { MenuOption(value: $0, title: $0) }, width: 130, mono: true)
                Spacer(minLength: 8)
                Tag(text: count == 1 ? "1 label" : "\(count) labels")
                IconButton(symbol: "trash", label: "Delete \(skill.name)", action: remove)
            }
            DField(placeholder: "Examples, separated by ;", text: Binding(get: { skill.examples.joined(separator: "; ") },
                                                                        set: { skill.examples = $0.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }),
                   symbol: "text.quote")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Look.canvas.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Look.line))
    }
}

// MARK: Labels

struct LabelsView: View {
    @Bindable var app: AppModel
    @State private var selection = Set<UUID>()
    @State private var anchor: UUID?
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
        let rows = shown
        VStack(spacing: 0) {
            PageHeader(title: "Labels",
                       subtitle: "\(app.labels.count) sentences · \(app.labels.filter { $0.set == "test" }.count) held out for testing · \(app.invalid.count) need fixing") {
                HStack(spacing: 8) {
                    DField(placeholder: "Search", text: $search, symbol: "magnifyingglass", width: 180)
                    DMenu(label: "Skill", selection: $skillFilter, options: filterOptions, width: 160)
                    Button(sample == nil ? "Spot-Check 20" : "Show All") {
                        sample = sample == nil ? Array(app.labels.shuffled().prefix(20).map(\.id)) : nil
                    }
                    .buttonStyle(DButton())
                    Button { app.delete(selection); selection = [] } label: { Label("Delete", systemImage: "trash") }
                        .buttonStyle(DButton(kind: .danger)).disabled(selection.isEmpty)
                }
            }
            VStack(spacing: 0) {
                if rows.isEmpty {
                    header
                    EmptyState(symbol: app.labels.isEmpty ? "tablecells" : "magnifyingglass",
                               title: app.labels.isEmpty ? "No labels yet" : "No labels match",
                               detail: app.labels.isEmpty ? "Make some on the Make Labels page, or send them from an agent over MCP." : "Try another search or skill.")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        // The headers ride in the scroll view so they share the rows' width (a scroller gutter can't shift them).
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) { SwiftUI.Section(header: header) {
                            ForEach(rows) { l in
                                LabelRowView(label: l, problem: l.problem(in: app.catalog), selected: selection.contains(l.id),
                                             edit: { editing = l })
                                    .contentShape(Rectangle())
                                    .onTapGesture { click(l.id, in: rows) }
                                    .contextMenu { menu(for: l.id) }
                                    .accessibilityAddTraits(selection.contains(l.id) ? [.isButton, .isSelected] : .isButton)
                                    .accessibilityAction(named: "Edit") { editing = l }
                            }
                        } }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(Look.card))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Look.line))
            .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
            .padding(20)
            .focusable()
            .focusEffectDisabled()
            .onDeleteCommand { app.delete(selection); selection = [] }
        }
        .sheet(item: $editing) { l in LabelEditor(label: l, catalog: app.catalog) { app.update($0) } }
    }

    private var filterOptions: [MenuOption<String>] {
        [MenuOption(value: "all", title: "All skills", icon: .symbol("square.stack")),
         MenuOption(value: "invalid", title: "Need fixing", icon: .symbol("exclamationmark.triangle"))]
            + app.catalog.skills.enumerated().map { i, s in MenuOption(value: s.key, title: s.name, separatorBefore: i == 0) }
            + [MenuOption(value: "none", title: "none")]
    }

    private var header: some View {
        HStack(spacing: 16) {
            col("Said").frame(maxWidth: .infinity, alignment: .leading)
            col("Steps").frame(maxWidth: .infinity, alignment: .leading)
            col("Set").frame(width: 56, alignment: .leading)
            col("From").frame(width: 70, alignment: .leading)
            Color.clear.frame(width: 28)
        }
        .padding(.horizontal, 18).frame(height: 36)
        .background(Look.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Look.line).frame(height: 1) }
    }
    private func col(_ t: String) -> some View { Text(t.uppercased()).font(.ui(11, .semibold)).kerning(0.5).foregroundStyle(Look.muted) }

    /// Click selects one; ⌘ adds or removes; ⇧ selects the range; a double click edits.
    private func click(_ id: UUID, in rows: [Labeled]) {
        let keys = NSEvent.modifierFlags
        if NSApp.currentEvent?.clickCount == 2 { editing = app.labels.first { $0.id == id }; return }
        if keys.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else if keys.contains(.shift), let a = anchor, let i = rows.firstIndex(where: { $0.id == a }), let j = rows.firstIndex(where: { $0.id == id }) {
            selection = Set(rows[min(i, j)...max(i, j)].map(\.id))
        } else {
            selection = [id]; anchor = id
        }
    }

    @ViewBuilder private func menu(for id: UUID) -> some View {
        let ids = selection.contains(id) ? selection : [id]
        Button("Edit") { editing = app.labels.first { $0.id == id } }.disabled(ids.count != 1)
        Button("Move to Test") { for id in ids { if var l = app.labels.first(where: { $0.id == id }) { l.set = "test"; app.update(l) } } }
        Button("Move to Train") { for id in ids { if var l = app.labels.first(where: { $0.id == id }) { l.set = "train"; app.update(l) } } }
        Divider()
        Button("Delete", role: .destructive) { app.delete(ids); selection.subtract(ids) }
    }
}

struct LabelRowView: View {
    let label: Labeled
    let problem: String?
    let selected: Bool
    let edit: () -> Void
    @State private var hover = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if problem != nil {
                        Image(systemName: "exclamationmark.triangle.fill").font(.ui(11.5)).foregroundStyle(Color.mtWarn).help(problem ?? "")
                            .accessibilityLabel("Needs fixing: \(problem ?? "")")
                    }
                    Text(label.said).font(.ui(13.5)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(label.steps.indices, id: \.self) { i in
                        let s = label.steps[i]
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(s.text).font(.ui(12.5)).foregroundStyle(Look.muted).lineLimit(2)
                            Image(systemName: "arrow.right").font(.ui(9, .bold)).foregroundStyle(Look.faint)
                            Tag(text: s.skill, mono: true, tint: s.skill == "none" ? nil : Look.ink)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Tag(text: label.set, tint: label.set == "test" ? Color.mtWarn : label.set == "real" ? Color.mtGood : nil)
                    .frame(width: 56, alignment: .leading)
                Text(label.source).font(.ui(12.5)).foregroundStyle(Look.muted).lineLimit(1).frame(width: 70, alignment: .leading)
                IconButton(symbol: "pencil", label: "Edit", action: edit).opacity(hover ? 1 : 0)
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(selected ? Look.chosen : hover ? Look.hover : .clear)
            Rectangle().fill(Look.line).frame(height: 1)
        }
        .onHover { hover = $0 }
    }
}

struct LabelEditor: View {
    @State var label: Labeled
    let catalog: Catalog
    let save: (Labeled) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let skills = catalog.skills.map { MenuOption(value: $0.key, title: $0.name) } + [MenuOption(value: "none", title: "none")]
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Label").font(.ui(18, .semibold))
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Said")
                DField(placeholder: "What was said", text: $label.said)
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("Steps")
                ForEach(label.steps.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        DField(placeholder: "Step text", text: $label.steps[i].text)
                        DMenu(label: "Skill", selection: $label.steps[i].skill, options: skills, width: 200)
                        IconButton(symbol: "minus.circle", label: "Remove step") { label.steps.remove(at: i) }.disabled(label.steps.count == 1)
                    }
                }
                Button { label.steps.append(Step(text: "", skill: catalog.skills.first?.key ?? "none")) } label: { Label("Add Step", systemImage: "plus") }
                    .buttonStyle(DButton(small: true))
            }
            HStack(spacing: 12) {
                FieldLabel("Set")
                DSegmented(label: "Set", selection: $label.set, options: [("train", "Train"), ("test", "Test"), ("real", "Real")])
            }
            if let p = label.problem(in: catalog) { Problems(items: [p]) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(DButton())
                Button("Save") { save(label); dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(DButton(kind: .primary))
                    .disabled(label.problem(in: catalog) != nil)
            }
        }
        .padding(26)
        .frame(width: 640)
        .background(Look.panel)
    }
}

// MARK: Making labels

extension AIProvider {
    var icon: MenuIcon {
        switch self {
        case .claude, .anthropic: .dot(.mtClaude)
        case .chatgpt, .openai: .dot(.mtChatGPT)
        case .gemini, .google: .dot(Look.gemini)
        case .compatible: .dot(Look.muted)
        }
    }
}

struct GenerateView: View {
    @Bindable var app: AppModel
    @State private var provider = AISettings.provider
    @State private var target = Setup.target

    var body: some View {
        let gen = app.generator
        Page(title: "Make Labels", subtitle: "Labels are example commands with the right steps and skills. A good model needs thousands; Tars 0.5 was trained on about 8,400.") {
            Problems(items: app.catalog.problems)
            Card(title: "With your AI provider", detail: "Your catalog and the prompts go to the provider you pick. Subscriptions run their own command line tool on this Mac; API keys stay in your Keychain.") {
                SettingRow(title: "Provider") {
                    HStack(spacing: 10) {
                        let st = provider.status
                        StatusPill(ok: st == .ready, text: st.title)
                        DMenu(label: "Provider", selection: $provider, options: AIProvider.allCases.map { MenuOption(value: $0, title: $0.title, icon: $0.icon) })
                            .onChange(of: provider) { AISettings.provider = provider }
                    }
                }
                SettingRow(title: "Target", detail: "How many labels to have in total.", last: true) {
                    HStack(spacing: 8) {
                        DStepper(value: $target, range: 1...1_000_000, step: 100, label: "Target labels")
                            .onChange(of: target) { Setup.target = max(1, target) }
                        Text("labels").font(.ui(13)).foregroundStyle(Look.muted)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Progress").font(.ui(12.5, .medium))
                        Spacer()
                        Text("\(app.labels.count) of \(target)").font(.ui(12.5)).foregroundStyle(Look.muted).monospacedDigit()
                    }
                    DProgress(value: Double(min(app.labels.count, target)) / Double(max(target, 1)))
                }
                .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Look.field))
                HStack(spacing: 10) {
                    if gen.running {
                        Button { gen.stop() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(DButton())
                        Pulse()
                        Text("\(gen.asked) requests, \(gen.failed) failed").font(.ui(12.5)).foregroundStyle(Look.muted)
                    } else {
                        Button { gen.start(app, target: target) } label: { Label("Start Making Labels", systemImage: "sparkles") }
                            .buttonStyle(DButton(kind: .primary))
                            .disabled(!app.catalog.problems.isEmpty || provider.status != .ready || app.demo)
                    }
                }
                if let e = gen.lastError { Notice(text: e, symbol: "xmark.octagon.fill", tint: .mtBad) }
                if !gen.lastRejected.isEmpty {
                    DDisclosure(title: "\(gen.lastRejected.count) rejected in the last batch") {
                        CodeWell(text: gen.lastRejected.prefix(12).joined(separator: "\n"))
                    }
                }
            }
            Card(title: "With any agent (MCP)", detail: "Tars runs an MCP server so Claude Code, Codex or any MCP client can write labels. They get your catalog and the label rules, and every label they send is checked before it's kept.") {
                let cmd = "claude mcp add tars -- \(Bundle.main.executablePath ?? "/Applications/Tars.app/Contents/MacOS/Tars") --mcp"
                HStack(alignment: .center, spacing: 10) {
                    Text(cmd).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cmd, forType: .string) } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(DButton(small: true))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Look.field))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Look.line))
                Text("Then ask it: \"Use the tars tools to write 500 labels, thinnest skills first.\" Tools: get_catalog, get_label_schema, submit_labels, get_progress.")
                    .font(.ui(12)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true)
            }
            Card(title: "Coverage", detail: "Labels per skill. Thin skills are the ones to fill next.") {
                let counts = app.skillCounts
                let most = max(1, counts.values.max() ?? 1)
                VStack(spacing: 9) {
                    ForEach(app.catalog.skills + [Skill(key: "none", family: "none", name: "Not a request", examples: [])]) { s in
                        HStack(spacing: 12) {
                            Text(s.name).font(.ui(13)).frame(width: 230, alignment: .leading).lineLimit(1)
                            GeometryReader { g in
                                Capsule().fill(Look.pill)
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Look.ink.opacity(0.85)).frame(width: max(4, g.size.width * CGFloat(counts[s.key] ?? 0) / CGFloat(most)))
                                    }
                            }.frame(height: 8)
                            Text("\(counts[s.key] ?? 0)").font(.ui(12.5)).monospacedDigit().frame(width: 44, alignment: .trailing).foregroundStyle(Look.muted)
                        }
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
                SettingRow(title: "Time budget", detail: "Training stops at this limit and keeps the best checkpoint.") {
                    HStack(spacing: 12) {
                        DSlider(value: $minutes, range: 10...240, step: 10, label: "Time budget", valueText: "\(Int(minutes)) minutes")
                            .frame(width: 220)
                            .onChange(of: minutes) { Setup.minutes = minutes }
                        Text("\(Int(minutes)) min").font(.ui(13, .medium)).monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                SettingRow(title: "Quick test run", detail: "A few steps, to check the setup works.", last: true) {
                    DSwitch(label: "Quick test run", on: $trainer.quick)
                }
                HStack(spacing: 10) {
                    if trainer.running {
                        Button { trainer.stop() } label: { Label("Stop and Keep Best", systemImage: "stop.fill") }.buttonStyle(DButton())
                        Button(role: .destructive) { trainer.cancel() } label: { Text("Cancel") }.buttonStyle(DButton(kind: .danger))
                    } else {
                        Button { trainer.start() } label: { Label("Start Training", systemImage: "play.fill") }
                            .buttonStyle(DButton(kind: .primary)).disabled(!problems.isEmpty || app.labels.isEmpty)
                    }
                    if let s = trainer.exitStatus { StatusPill(ok: s == 0, text: s == 0 ? "Finished" : "Stopped (exit \(s))") }
                }
            }
            StageCard(progress: trainer.progress)
            if let r = trainer.report, let v = r.verdict {
                Card(title: "Verdict") {
                    HStack(spacing: 10) {
                        Image(systemName: v == "PROMOTE" ? "checkmark.seal.fill" : "xmark.seal").font(.ui(20)).foregroundStyle(v == "PROMOTE" ? Color.mtGood : Color.mtWarn)
                        Text(v == "PROMOTE" ? "Better than the base model" : "Not better yet").font(.ui(15, .semibold))
                    }
                    Text((r.reasons ?? []).joined(separator: " · ")).font(.ui(12.5)).foregroundStyle(Look.muted)
                }
            }
            Card(title: "Export", detail: "Copies the fine-tuned checkpoint and your catalog into a folder. Load it with Planner(Catalog.load(\"catalog.json\"), \"tars-model\").") {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Export Here"
                    if panel.runModal() == .OK, let u = panel.url {
                        do { try trainer.export(to: u, catalog: app.catalog); exportError = nil } catch { exportError = error.localizedDescription }
                    }
                } label: { Label("Export Model…", systemImage: "square.and.arrow.up") }
                .buttonStyle(DButton())
                .disabled(!trainer.hasCandidate)
                if let exportError { Notice(text: exportError, symbol: "xmark.octagon.fill", tint: .mtBad) }
            }
            Card(title: "Log") {
                CodeWell(text: trainer.logTail.isEmpty ? "Nothing yet." : trainer.logTail)
            }
        }
    }
}

struct StageCard: View {
    let progress: Progress
    static let stages = ["building", "evaluating", "training", "done"]
    var body: some View {
        Card(title: "Progress") {
            let now = progress.stage ?? ""
            let idx = Self.stages.firstIndex(of: now) ?? -1
            HStack(spacing: 10) {
                ForEach(Self.stages, id: \.self) { s in
                    let mine = Self.stages.firstIndex(of: s)!
                    let done = mine < idx || now == "done"
                    HStack(spacing: 7) {
                        ZStack {
                            Circle().fill(done ? Look.ink : mine == idx ? Look.card : Look.pill)
                            Circle().strokeBorder(mine == idx ? Look.ink : Look.line, lineWidth: mine == idx ? 1.5 : 1)
                            if done { Image(systemName: "checkmark").font(.ui(9, .bold)).foregroundStyle(Look.onInk) }
                            else if mine == idx { Circle().fill(Look.ink).frame(width: 6, height: 6) }
                        }
                        .frame(width: 20, height: 20)
                        Text(s.capitalized).font(.ui(13, mine == idx ? .semibold : .medium)).foregroundStyle(mine <= idx ? Look.ink : Look.muted)
                            .fixedSize()
                    }
                    if s != "done" { Capsule().fill(mine < idx ? Look.ink : Look.line).frame(height: 2) }
                }
            }
            if let t = progress.train, let step = t.step {
                HStack(spacing: 10) {
                    Stat(value: "\(step)", label: "steps")
                    Stat(value: String(format: "%.0f / %.0f min", t.elapsed_min ?? 0, t.budget_min ?? 0), label: "time")
                    Stat(value: pct(t.best?.val), label: "best validation")
                    Stat(value: pct(t.baseline?.val), label: "base model")
                }
            }
            if let m = progress.message, !m.isEmpty { Text(m).font(.ui(12.5)).foregroundStyle(Look.muted) }
        }
    }
}
