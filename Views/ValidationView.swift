import SwiftUI
import Charts
import UniformTypeIdentifiers

/// 途中データからの予測が、最終データとどれくらい合っていたかを確かめる画面
struct ValidationView: View {
    @Environment(BankStore.self) private var bankStore
    @Environment(ValidationStore.self) private var store

    @State private var preset: PriorPreset = .uniform
    @State private var customPercents: [Int] = [40, 25, 15, 10, 6, 4]
    @State private var editing: ValidationRecord?
    @State private var showImporter = false
    @State private var importMessage: String?

    private var prior: [Double] {
        let p = preset.percents ?? customPercents.map(Double.init)
        return p.reduce(0, +) > 0 ? p : [1, 1, 1, 1, 1, 1]
    }

    private var summary: ValidationSummary {
        PredictionCheck.summarize(store.records, spec: bankStore.spec, prior: prior)
    }

    var body: some View {
        NavigationStack {
            Form {
                priorSection
                let s = summary
                if s.checks.isEmpty {
                    Section {
                        Text("最終データまで入った記録がまだありません。下の「記録」から追加するか、CSVを取り込んでください。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    coverageSection(s)
                    bucketSection(s)
                }
                recordsSection
            }
            .navigationTitle("予測の検証")
            .sheet(item: $editing) { r in
                RecordEditView(record: r) { store.upsert($0) }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                importCSV(result)
            }
            .alert("CSVの取り込み", isPresented: Binding(get: { importMessage != nil },
                                                    set: { if !$0 { importMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    // MARK: - 前提

    private var priorSection: some View {
        Section {
            Picker("店の設定配分", selection: $preset) {
                ForEach(PriorPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            if preset == .custom {
                ForEach(0..<6, id: \.self) { i in
                    IntField(title: "設定\(i + 1)（%）", value: $customPercents[i])
                }
            } else if let p = preset.percents {
                Text(p.enumerated().map { "設定\($0.offset + 1) \(Int($0.element.rounded()))%" }.joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("予測の前提")
        } footer: {
            Text("途中データから設定を推測するときの前提です。前提を変えると予測が変わるので、どの前提がいちばん実績と合うかを比べられます。")
        }
    }

    // MARK: - 結果

    private func coverageSection(_ s: ValidationSummary) -> some View {
        Section {
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("50%範囲")
                    Text("90%範囲")
                    Text("予測の合計")
                    Text("実際")
                }
                .font(.caption.bold())
                Divider()
                coverageRow("BIG", s.big, unit: "回")
                coverageRow("REG", s.reg, unit: "回")
                coverageRow("差枚", s.diff, unit: "枚")
            }
            .font(.footnote.monospacedDigit())

            if let reg = s.reg {
                pitChart(title: "REG回数の予測に対する実際の位置", reg.histogram)
            }
            if let diff = s.diff {
                pitChart(title: "差枚の予測に対する実際の位置", diff.histogram)
            }
        } header: {
            Text("その後の予測は当たったか（\(s.checks.count)台）")
        } footer: {
            Text("「50%範囲」「90%範囲」は、予測した範囲に実際の値が入った割合です。予測が正しければ、それぞれ50%・90%前後になります。下のグラフは、実際の値が予測のどのあたりに来たかの分布で、正しければ平らになります。左に偏れば予測が楽観的、右に偏れば悲観的です。差枚は小役のブレを入れていないモデルなので、範囲が実際より狭めに出ます。")
        }
    }

    @ViewBuilder
    private func coverageRow(_ name: String, _ c: CoverageStat?, unit: String) -> some View {
        if let c {
            GridRow {
                Text(name).gridColumnAlignment(.leading)
                Text(Fmt.pct(c.cover50)).foregroundStyle(color(c.cover50, ideal: 0.5))
                Text(Fmt.pct(c.cover90)).foregroundStyle(color(c.cover90, ideal: 0.9))
                Text(unit == "枚" ? Fmt.signed(c.predictedTotal) : String(format: "%.1f", c.predictedTotal))
                Text(unit == "枚" ? Fmt.signed(c.actualTotal) : String(format: "%.0f", c.actualTotal))
            }
        } else {
            GridRow {
                Text(name).gridColumnAlignment(.leading)
                Text("—"); Text("—"); Text("差枚の記録なし").foregroundStyle(.secondary); Text("")
            }
        }
    }

    /// 理想から大きく外れていたら色を付ける（件数が少ないうちは外れやすいので目安）
    private func color(_ v: Double, ideal: Double) -> Color {
        abs(v - ideal) <= 0.1 ? .primary : .orange
    }

    private func pitChart(title: String, _ h: [Int]) -> some View {
        let total = max(h.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            Chart {
                ForEach(h.indices, id: \.self) { i in
                    BarMark(x: .value("位置", "\(i * 10)"),
                            y: .value("割合", Double(h[i]) / Double(total)))
                        .foregroundStyle(.blue.opacity(0.7))
                }
                RuleMark(y: .value("理想", 0.1))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartXAxis {
                AxisMarks(values: ["0", "50", "90"]) { v in
                    AxisValueLabel {
                        if let s = v.as(String.self) {
                            Text(s == "0" ? "予測より少" : s == "90" ? "予測より多" : "中央")
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.pct(d)) } }
                }
            }
            .frame(height: 120)
        }
    }

    private func bucketSection(_ s: ValidationSummary) -> some View {
        Section {
            ForEach(s.buckets) { b in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("設定4以上の確率 \(b.label)").bold()
                        Spacer()
                        Text("\(b.count)台")
                    }
                    Text("その後のREG：予測 \(Fmt.denom(b.predictedRegDenom)) → 実際 \(Fmt.denom(b.actualRegDenom))")
                    if let p = b.predictedRate, let a = b.actualRate {
                        Text(String(format: "その後の機械割：予測 %.1f%% → 実際 %.1f%%", p, a))
                    }
                }
                .font(.footnote.monospacedDigit())
            }
        } header: {
            Text("設定推測は当たっていたか")
        } footer: {
            Text("途中の時点で「設定4以上の確率」がどれくらいと出ていた台かで分け、その後のREG確率と機械割を比べています。推測が正しければ、確率が高いグループほど実際のREG確率も機械割も良くなり、予測と実際が近くなります。1グループ数十台以上ないと、偶然のブレが大きいので注意してください。")
        }
    }

    // MARK: - 記録

    private var recordsSection: some View {
        Section {
            Button {
                var r = ValidationRecord()
                r.checkGames = 2000
                editing = r
            } label: {
                Label("記録を追加", systemImage: "plus")
            }
            Button {
                showImporter = true
            } label: {
                Label("CSVを取り込む", systemImage: "square.and.arrow.down")
            }
            if !store.records.isEmpty, let url = exportURL() {
                ShareLink(item: url) {
                    Label("CSVで書き出す", systemImage: "square.and.arrow.up")
                }
            }

            ForEach(store.records) { r in
                Button { editing = r } label: { recordRow(r) }
                    .foregroundStyle(.primary)
            }
            .onDelete { idx in
                store.delete(ids: Set(idx.map { store.records[$0].id }))
            }
        } header: {
            Text("記録（\(store.records.count)件）")
        } footer: {
            Text("CSVの列：\(ValidationCSV.header)\n差枚は分からなければ空欄で構いません。最終データが空欄の記録は「未完了」として検証から外します。")
        }
    }

    private func recordRow(_ r: ValidationRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(r.date, format: .dateTime.year().month().day())
                if let u = r.unit { Text("\(u)番") }
                Spacer()
                if !r.isComplete {
                    Text("未完了").font(.caption).foregroundStyle(.orange)
                }
            }
            .font(.subheadline)
            Text("途中 \(r.checkGames)G B\(r.checkBig) R\(r.checkReg)"
                 + (r.isComplete ? " → 最終 \(r.finalGames ?? 0)G B\(r.finalBig ?? 0) R\(r.finalReg ?? 0)" : ""))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func exportURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("slot-validation.csv")
        do {
            try ValidationCSV.make(store.records).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func importCSV(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            importMessage = "ファイルを開けませんでした。"
            return
        }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = ValidationCSV.decode(data) else {
            importMessage = "ファイルを読めませんでした。"
            return
        }
        let parsed = ValidationCSV.parse(text)
        store.append(parsed.records)
        importMessage = "\(parsed.records.count)件を取り込みました。"
            + (parsed.skipped > 0 ? "\n読めなかった行：\(parsed.skipped)行" : "")
    }
}

/// 1件の記録を入力・編集する画面
struct RecordEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var record: ValidationRecord
    var onSave: (ValidationRecord) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日付", selection: $record.date, displayedComponents: .date)
                    optionalField("台番", $record.unit)
                }
                Section {
                    IntField(title: "G数", value: $record.checkGames)
                    IntField(title: "BIG", value: $record.checkBig)
                    IntField(title: "REG", value: $record.checkReg)
                    optionalField("差枚", $record.checkDiff)
                } header: {
                    Text("途中（判断する時点）")
                } footer: {
                    Text("例：2000G回った時点のデータ。打ち始める前に見たデータでも構いません。")
                }
                Section {
                    optionalField("G数", $record.finalGames)
                    optionalField("BIG", $record.finalBig)
                    optionalField("REG", $record.finalReg)
                    optionalField("差枚", $record.finalDiff)
                } header: {
                    Text("最終（閉店時など）")
                } footer: {
                    Text("あとから入力できます。G数・BIG・REGはその日の合計（途中の分を含む）を入れてください。")
                }
            }
            .navigationTitle("記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(record)
                        dismiss()
                    }
                }
            }
        }
    }

    private func optionalField(_ title: String, _ value: Binding<Int?>) -> some View {
        LabeledContent(title) {
            TextField("未入力", value: value, format: .number)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
        }
    }
}
