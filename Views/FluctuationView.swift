import SwiftUI
import Charts

/// 設定ごとのスランプグラフの揺れ幅と、G数ごとの設定の見分けやすさ
struct FluctuationView: View {
    @Environment(BankStore.self) private var store
    /// グラフに表示する設定（既定は 1 と 6）
    @State private var visible: Set<Int> = [0, 5]
    @State private var showInner = true
    /// グラフに表示する最大ゲーム数（0 = シミュレーションの最大まで）
    @State private var displayGames = 0
    /// 表示範囲に合わせて計算し直した帯
    @State private var visibleBands: [BandPoint] = []

    private static let rangeChoices = [100, 200, 500, 1000, 2000, 4000, 8000, 10000]

    private var effectiveGames: Int {
        guard let bank = store.bank else { return 0 }
        return displayGames > 0 ? min(displayGames, bank.maxGames) : bank.maxGames
    }

    var body: some View {
        NavigationStack {
            Form {
                BankControlSection()

                if store.bank != nil {
                    chartSection
                    ForEach(store.checkpoints) { cp in
                        checkpointSection(cp)
                    }
                }
            }
            .navigationTitle("揺れ分析")
        }
    }

    private var chartSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(store.spec.labels.indices, id: \.self) { i in
                        let on = visible.contains(i)
                        Button("設定\(store.spec.labels[i])") {
                            if on { visible.remove(i) } else { visible.insert(i) }
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? color(i) : .gray)
                    }
                }
            }
            Toggle("50%の範囲も表示", isOn: $showInner)
            if let bank = store.bank {
                Picker("表示範囲", selection: $displayGames) {
                    ForEach(Self.rangeChoices.filter { $0 < bank.maxGames }, id: \.self) {
                        Text("\($0)G").tag($0)
                    }
                    Text("\(bank.maxGames)G（最大）").tag(0)
                }
            }

            let pts = visibleBands.filter { visible.contains($0.setting) }
            let yScale = AxisScale.nice(min: pts.map(\.p5).min() ?? -100,
                                        max: pts.map(\.p95).max() ?? 100)
            let xScale = AxisScale.nice(min: 0, max: Double(effectiveGames), targetTicks: 5)
            Chart {
                ForEach(pts) { b in
                    AreaMark(x: .value("G", Double(b.games)),
                             yStart: .value("下位5%", b.p5),
                             yEnd: .value("上位5%", b.p95),
                             series: .value("帯", "90-\(b.label)"))
                        .foregroundStyle(color(b.setting).opacity(0.12))
                    if showInner {
                        AreaMark(x: .value("G", Double(b.games)),
                                 yStart: .value("下位25%", b.p25),
                                 yEnd: .value("上位25%", b.p75),
                                 series: .value("帯", "50-\(b.label)"))
                            .foregroundStyle(color(b.setting).opacity(0.22))
                    }
                    LineMark(x: .value("G", Double(b.games)), y: .value("中央値", b.p50),
                             series: .value("設定", b.label))
                        .foregroundStyle(color(b.setting))
                }
                RuleMark(y: .value("0", 0)).foregroundStyle(.secondary.opacity(0.5))
            }
            .chartXScale(domain: 0...Double(effectiveGames))
            .chartXAxis {
                AxisMarks(values: xScale.ticks.filter { $0 <= Double(effectiveGames) }) { _ in
                    AxisGridLine(); AxisTick(); AxisValueLabel()
                }
            }
            .chartYScale(domain: yScale.domain)
            .chartYAxis {
                AxisMarks(position: .leading, values: yScale.ticks) { value in
                    AxisGridLine(); AxisTick()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Fmt.signed(v)) }
                    }
                }
            }
            .chartXAxisLabel("ゲーム数")
            .chartYAxisLabel("差枚")
            .task(id: bandKey) { recomputeBands() }
            .frame(height: 280)
        } header: {
            Text("差枚の揺れ幅")
        } footer: {
            Text("線は中央値、薄い帯は90%の台が収まる範囲、濃い帯は50%の範囲です。縦軸は表示範囲のゲーム数に合わせて自動で調整されます。帯が重なっている区間は、グラフの形だけでは設定を見分けにくい区間です。")
        }
    }

    private func checkpointSection(_ cp: CheckpointStat) -> some View {
        Section {
            ForEach(cp.rows) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("設定\(r.label)").bold().foregroundStyle(color(r.setting))
                        Spacer()
                        Text("勝率 \(Fmt.pct(r.winRate))")
                    }
                    Text("差枚 \(Fmt.signed(r.diffP5)) 〜 \(Fmt.signed(r.diffP95))（中央 \(Fmt.signed(r.diffP50))）")
                    Text("合算 \(Fmt.denom(r.combinedLuckyDenom)) 〜 \(Fmt.denom(r.combinedUnluckyDenom))")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote.monospacedDigit())
            }
        } header: {
            Text("\(cp.games)G 時点")
        } footer: {
            Text("BIG/REG回数からの推測で、設定をぴったり当てられる割合 \(Fmt.pct(cp.exactAccuracy))、設定4以上かどうかを当てられる割合 \(Fmt.pct(cp.highLowAccuracy))。範囲は各設定の90%の台が収まる幅です。")
        }
    }

    /// 表示範囲かシミュレーションが変わったら帯を計算し直す
    private var bandKey: String {
        guard let bank = store.bank else { return "none" }
        return "\(ObjectIdentifier(bank).hashValue)-\(effectiveGames)"
    }

    private func recomputeBands() {
        guard let bank = store.bank else { visibleBands = []; return }
        visibleBands = effectiveGames >= bank.maxGames
            ? store.bands
            : bank.bands(upToGames: effectiveGames)
    }

    private func color(_ i: Int) -> Color {
        let palette: [Color] = [.blue, .teal, .green, .yellow, .orange, .red]
        return palette[i % palette.count]
    }
}
