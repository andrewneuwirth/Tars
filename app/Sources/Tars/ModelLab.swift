import SwiftUI
import Charts
import MacToolsKit

/// Watch a run, compare your model with the base model, look back at past runs, and try a command on both.
struct ModelLabView: View {
    @Bindable var app: AppModel
    @Bindable var trainer: Trainer
    @State private var said = "open tunebox and play some jazz"

    var body: some View {
        Page(title: "Model Lab", subtitle: "How training is going, and how your model decides compared with the base model.") {
            HStack(alignment: .top, spacing: MT.Space.s18) {
                Card(title: "Loss") { Curve(points: trainer.progress.train?.loss ?? [], color: .mtBad, percent: false) }
                Card(title: "Training accuracy") { Curve(points: trainer.progress.train?.acc ?? [], color: .mtGood, percent: true) }
            }
            Card(title: "Checks during this run") { ChecksTable(baseline: trainer.progress.train?.baseline, checks: trainer.progress.train?.checks ?? []) }
            Card(title: "Your model vs the base model") { Comparison(report: trainer.report) }
            Card(title: "Try a command") {
                HStack {
                    TextField("Something you'd say", text: $said).textFieldStyle(.roundedBorder).onSubmit { trainer.tryCommand(said) }
                    Button(trainer.trying ? "Deciding…" : "Decide") { trainer.tryCommand(said) }
                        .disabled(trainer.trying || app.demo || !trainer.hasCandidate)
                }
                if !trainer.hasCandidate && !app.demo { Text("Train a model first; this runs both models on this Mac.").font(.caption).foregroundStyle(Color.mtInkMuted) }
                if let e = trainer.tryError { Text(e).font(.caption.monospaced()).foregroundStyle(Color.mtBad).textSelection(.enabled) }
                HStack(alignment: .top, spacing: MT.Space.s18) {
                    DecisionColumn(title: "Base model", decision: trainer.tryResult["base"])
                    DecisionColumn(title: "Your model", decision: trainer.tryResult["candidate"])
                }
            }
            Card(title: "Past runs") { RunsTable(runs: trainer.runs) }
        }
    }
}

struct Curve: View {
    let points: [[Double]]
    let color: Color
    let percent: Bool
    var body: some View {
        if points.isEmpty {
            Text("Starts when training does.").foregroundStyle(Color.mtInkMuted).frame(height: 180)
        } else {
            Chart(points.filter { $0.count == 2 }, id: \.self) { p in
                LineMark(x: .value("Step", p[0]), y: .value(percent ? "Accuracy" : "Loss", p[1])).foregroundStyle(color).interpolationMethod(.monotone)
            }
            .chartYAxis { AxisMarks { v in
                AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(percent ? "\(Int(d * 100))%" : String(format: "%.2f", d)) } }
            } }
            .chartXAxisLabel("Step")
            .frame(height: 180)
        }
    }
}

struct ChecksTable: View {
    let baseline: Check?
    let checks: [Check]
    var body: some View {
        if checks.isEmpty && baseline == nil {
            Text("Validation is scored every few hundred steps.").foregroundStyle(Color.mtInkMuted)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow { ForEach(["Step", "Minutes", "Validation", "Held-out styles", "General reasoning"], id: \.self) { Text($0).font(.caption).foregroundStyle(Color.mtInkMuted) } }
                Divider()
                if let b = baseline { row("Base", b) }
                ForEach(checks, id: \.self) { c in row("\(c.step ?? 0)", c) }
            }
            .monospacedDigit()
        }
    }
    private func row(_ name: String, _ c: Check) -> some View {
        GridRow { Text(name); Text(c.minutes.map { String(format: "%.0f", $0) } ?? "–"); Text(pct(c.val)); Text(pct(c.test_style)); Text(pct(c.val_replay)) }
    }
}

struct Comparison: View {
    let report: EvalReport?
    static let rows: [(String, String)] = [("Whole sentence right", "sentence"), ("Splitting", "split"), ("Routing (family)", "route"), ("Skill choice", "skill")]

    var body: some View {
        if let r = report, let set = r.mainSet, let b = r.base?[set], let c = r.candidate?[set] {
            VStack(alignment: .leading, spacing: MT.Space.s12) {
                Chart {
                    ForEach(Self.rows.filter { b[$0.1] != nil }, id: \.1) { name, key in
                        BarMark(x: .value("Accuracy", b[key]!), y: .value("Question", name)).foregroundStyle(by: .value("Model", "Base model")).position(by: .value("Model", "Base model"))
                        BarMark(x: .value("Accuracy", c[key] ?? 0), y: .value("Question", name)).foregroundStyle(by: .value("Model", "Your model")).position(by: .value("Model", "Your model"))
                    }
                }
                .chartForegroundStyleScale(["Base model": Color.mtInkMuted.opacity(0.5), "Your model": Color.accentColor])
                .chartXScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%") } } }
                .frame(height: 200)
                HStack {
                    Stat(value: b["ms_per_question"].map { String(format: "%.0f ms", $0) } ?? "–", label: "base, per question")
                    Stat(value: c["ms_per_question"].map { String(format: "%.0f ms", $0) } ?? "–", label: "yours, per question")
                    Stat(value: r.base?["val_replay"]?["all"].map { String(format: "%.1f%%", $0) } ?? "–", label: "base, general reasoning")
                    Stat(value: r.candidate?["val_replay"]?["all"].map { String(format: "%.1f%%", $0) } ?? "–", label: "yours, general reasoning")
                }
                Text("Scored on \(Int(c["sentences"] ?? c["n"] ?? 0)) \(set == "test_real" ? "of your own sentences" : "held-out labels") the model never trained on. Same size as the base: 395M parameters.")
                    .font(.caption).foregroundStyle(Color.mtInkMuted)
            }
        } else {
            Text("Appears after a run's final comparison.").foregroundStyle(Color.mtInkMuted)
        }
    }
}

struct DecisionColumn: View {
    let title: String
    let decision: Decision?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if let ms = decision?.ms { Text(String(format: "%.0f ms", ms)).font(.caption).foregroundStyle(Color.mtInkMuted).monospacedDigit() }
            }
            if let e = decision?.error { Text(e).font(.caption).foregroundStyle(Color.mtBad) }
            ForEach(decision?.steps ?? [], id: \.self) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\"\(s.text)\"")
                    Text("\(s.family ?? "?") / \(s.skill ?? "–")  ·  \(pct(s.skill_p ?? s.family_p))").font(.caption.monospaced()).foregroundStyle(Color.mtInkMuted)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: MT.Radius.control).fill(Color.mtFillInset))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct RunsTable: View {
    let runs: [PastRun]
    var body: some View {
        if runs.isEmpty {
            Text("No runs yet.").foregroundStyle(Color.mtInkMuted)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow { ForEach(["Run", "Best step", "Validation", "Base", "Whole sentence", "Verdict"], id: \.self) { Text($0).font(.caption).foregroundStyle(Color.mtInkMuted) } }
                Divider()
                ForEach(runs) { r in
                    GridRow {
                        Text(r.date?.formatted(date: .abbreviated, time: .shortened) ?? r.id)
                        Text(r.best?.step.map(String.init) ?? "–")
                        Text(pct(r.best?.val))
                        Text(pct(r.baseline?.val))
                        Text(r.eval.flatMap { e in e.mainSet.flatMap { e.candidate?[$0]?["sentence"] } }.map { String(format: "%.1f%%", $0) } ?? "–")
                        Text(r.eval?.verdict ?? "–").foregroundStyle(r.eval?.verdict == "PROMOTE" ? Color.mtGood : Color.mtInkMuted)
                    }
                }
            }
            .monospacedDigit()
        }
    }
}
