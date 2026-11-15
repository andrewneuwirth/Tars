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
            SectionHeader(title: "This run")
            HStack(alignment: .top, spacing: 16) {
                Card(title: "Loss", detail: "Lower is better.") { Curve(points: trainer.progress.train?.loss ?? [], color: .mtBad, percent: false) }
                Card(title: "Training accuracy", detail: "Share of training examples right.") { Curve(points: trainer.progress.train?.acc ?? [], color: .mtGood, percent: true) }
            }
            Card(title: "Checks during this run", detail: "Scored on labels the model doesn't train on.") { ChecksTable(baseline: trainer.progress.train?.baseline, checks: trainer.progress.train?.checks ?? []) }
            SectionHeader(title: "Compare").padding(.top, 6)
            Card(title: "Your model vs the base model") { Comparison(report: trainer.report) }
            Card(title: "Try a command", detail: "Runs both models on this Mac and shows how each splits and routes it.") {
                HStack(spacing: 8) {
                    DField(placeholder: "Something you'd say", text: $said, symbol: "waveform") { trainer.tryCommand(said) }
                    Button { trainer.tryCommand(said) } label: { Label(trainer.trying ? "Deciding…" : "Decide", systemImage: "arrow.right") }
                        .buttonStyle(DButton(kind: .primary))
                        .disabled(trainer.trying || app.demo || !trainer.hasCandidate)
                }
                if !trainer.hasCandidate && !app.demo { Text("Train a model first; this runs both models on this Mac.").font(.ui(12)).foregroundStyle(Look.muted) }
                if let e = trainer.tryError { Notice(text: e, symbol: "xmark.octagon.fill", tint: .mtBad) }
                HStack(alignment: .top, spacing: 16) {
                    DecisionColumn(title: "Base model", decision: trainer.tryResult["base"])
                    DecisionColumn(title: "Your model", decision: trainer.tryResult["candidate"])
                }
            }
            SectionHeader(title: "History").padding(.top, 6)
            Card(title: "Past runs") { RunsTable(runs: trainer.runs) }
        }
    }
}

/// Axis styling shared by every chart: hairline grid, small muted labels.
extension View {
    func lookAxes(xLabel: String? = nil) -> some View {
        self
            .chartXAxis { AxisMarks { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Look.line); AxisValueLabel().font(.ui(10.5)).foregroundStyle(Look.muted) } }
    }
}

struct Curve: View {
    let points: [[Double]]
    let color: Color
    let percent: Bool
    var body: some View {
        if points.isEmpty {
            EmptyState(symbol: "chart.xyaxis.line", title: "No data yet", detail: "Starts when training does.", height: 180)
        } else {
            let pts = points.filter { $0.count == 2 }
            let lo = (pts.map { $0[1] }.min() ?? 0), hi = (pts.map { $0[1] }.max() ?? 1)
            let floor = percent ? max(0, lo - 0.05) : max(0, lo - (hi - lo) * 0.1)
            Chart(pts, id: \.self) { p in
                AreaMark(x: .value("Step", p[0]), yStart: .value("Floor", floor), yEnd: .value(percent ? "Accuracy" : "Loss", p[1]))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Step", p[0]), y: .value(percent ? "Accuracy" : "Loss", p[1]))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round)).interpolationMethod(.monotone)
            }
            .chartYScale(domain: floor...(percent ? min(1, hi + 0.03) : hi * 1.05))
            .chartXScale(domain: (pts.first?[0] ?? 0)...max((pts.last?[0] ?? 1) * 1.04, (pts.first?[0] ?? 0) + 1))   // room for the last tick's label
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Look.line)
                AxisValueLabel { if let d = v.as(Double.self) { Text(percent ? "\(Int(d * 100))%" : String(format: "%.1f", d)).font(.ui(10.5)).foregroundStyle(Look.muted) } }
            } }
            .lookAxes()
            .chartXAxisLabel(position: .bottom, alignment: .center) { Text("Step").font(.ui(10.5)).foregroundStyle(Look.muted) }
            .frame(height: 180)
        }
    }
}

/// A plain table on a card: small uppercase headers, hairlines between rows.
struct LookTable: View {
    let headers: [String]
    let rows: [[(String, Color?)]]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) { ForEach(headers.indices, id: \.self) { i in cell(i == 0 ? headers[i].uppercased() : headers[i].uppercased(), head: true, first: i == 0) } }
                .padding(.horizontal, 12).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Look.field))
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 12) {
                    ForEach(rows[r].indices, id: \.self) { i in cell(rows[r][i].0, tint: rows[r][i].1, first: i == 0) }
                }
                .padding(.horizontal, 12).frame(minHeight: 34)
                if r < rows.count - 1 { Rectangle().fill(Look.line).frame(height: 1).padding(.horizontal, 12) }
            }
        }
        .monospacedDigit()
    }
    private func cell(_ t: String, head: Bool = false, tint: Color? = nil, first: Bool) -> some View {
        Text(t)
            .font(head ? .ui(10.5, .semibold) : .ui(13, first ? .medium : .regular))
            .kerning(head ? 0.5 : 0)
            .foregroundStyle(head ? Look.muted : tint ?? Look.ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChecksTable: View {
    let baseline: Check?
    let checks: [Check]
    var body: some View {
        if checks.isEmpty && baseline == nil {
            EmptyState(symbol: "checklist", title: "No checks yet", detail: "Validation is scored every few hundred steps.", height: 120)
        } else {
            LookTable(headers: ["Step", "Minutes", "Validation", "Held-out styles", "General reasoning"],
                      rows: (baseline.map { [row("Base", $0)] } ?? []) + checks.map { row("\($0.step ?? 0)", $0) })
        }
    }
    private func row(_ name: String, _ c: Check) -> [(String, Color?)] {
        [(name, nil), (c.minutes.map { String(format: "%.0f", $0) } ?? "–", nil), (pct(c.val), nil), (pct(c.test_style), nil), (pct(c.val_replay), nil)]
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
                        BarMark(x: .value("Accuracy", b[key]!), y: .value("Question", name)).foregroundStyle(by: .value("Model", "Base model")).position(by: .value("Model", "Base model")).cornerRadius(4)
                        BarMark(x: .value("Accuracy", c[key] ?? 0), y: .value("Question", name)).foregroundStyle(by: .value("Model", "Your model")).position(by: .value("Model", "Your model")).cornerRadius(4)
                    }
                }
                .chartForegroundStyleScale(["Base model": Look.track, "Your model": Look.ink])
                .chartXScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Look.line)
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.ui(10.5)).foregroundStyle(Look.muted) }
                } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().font(.ui(12)).foregroundStyle(Look.ink) } }
                .chartLegend(position: .top, alignment: .leading, spacing: 12)
                .frame(height: 220)
                HStack(spacing: 10) {
                    Stat(value: b["ms_per_question"].map { String(format: "%.0f ms", $0) } ?? "–", label: "base, per question")
                    Stat(value: c["ms_per_question"].map { String(format: "%.0f ms", $0) } ?? "–", label: "yours, per question")
                    Stat(value: r.base?["val_replay"]?["all"].map { String(format: "%.1f%%", $0) } ?? "–", label: "base, general reasoning")
                    Stat(value: r.candidate?["val_replay"]?["all"].map { String(format: "%.1f%%", $0) } ?? "–", label: "yours, general reasoning")
                }
                Text("Scored on \(Int(c["sentences"] ?? c["n"] ?? 0)) \(set == "test_real" ? "of your own sentences" : "held-out labels") the model never trained on. Same size as the base: 395M parameters.")
                    .font(.ui(12)).foregroundStyle(Look.muted)
            }
        } else {
            EmptyState(symbol: "chart.bar.xaxis", title: "No comparison yet", detail: "Appears after a run's final comparison.", height: 140)
        }
    }
}

struct DecisionColumn: View {
    let title: String
    let decision: Decision?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.ui(13, .semibold))
                Spacer()
                if let ms = decision?.ms { Tag(text: String(format: "%.0f ms", ms)) }
            }
            if let e = decision?.error { Text(e).font(.ui(12)).foregroundStyle(Color.mtBad) }
            if decision == nil {
                Text("No decision yet").font(.ui(12.5)).foregroundStyle(Look.faint)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Look.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            ForEach(decision?.steps ?? [], id: \.self) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\"\(s.text)\"").font(.ui(13))
                    HStack(spacing: 6) {
                        Tag(text: "\(s.family ?? "?") / \(s.skill ?? "–")", mono: true, tint: Look.ink)
                        Text(pct(s.skill_p ?? s.family_p)).font(.ui(11.5)).foregroundStyle(Look.muted).monospacedDigit()
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Look.field))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct RunsTable: View {
    let runs: [PastRun]
    var body: some View {
        if runs.isEmpty {
            EmptyState(symbol: "clock.arrow.circlepath", title: "No runs yet", detail: "Each finished training run is listed here.", height: 120)
        } else {
            LookTable(headers: ["Run", "Best step", "Validation", "Base", "Whole sentence", "Verdict"], rows: runs.map { r in
                [(r.date?.formatted(date: .abbreviated, time: .shortened) ?? r.id, nil),
                 (r.best?.step.map(String.init) ?? "–", nil),
                 (pct(r.best?.val), nil),
                 (pct(r.baseline?.val), nil),
                 (r.eval.flatMap { e in e.mainSet.flatMap { e.candidate?[$0]?["sentence"] } }.map { String(format: "%.1f%%", $0) } ?? "–", nil),
                 (r.eval?.verdict.map { $0 == "PROMOTE" ? "Better" : "Not better" } ?? "–", r.eval?.verdict == "PROMOTE" ? Color.mtGood : Look.muted)]
            })
        }
    }
}
