import SwiftUI
import Charts

/// 設定ごとのスランプグラフの揺れ幅と、G数ごとの設定の見分けやすさ
struct FluctuationView: View {
    @Environment(BankStore.self) private var store
    /// グラフに表示する設定（既定は 1 と 6）
    @State private var visible: Set<Int> = [0, 5]
    @State private var showInner = true

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

            let pts = store.bands.filter { visible.contains($0.setting) }
            Chart {
                ForEach(pts) { b in
                    AreaMark(x: .value("G", b.games),
                             yStart: .value("下位5%", b.p5),
                             yEnd: .value("上位5%", b.p95),
                             series: .value("帯", "90-\(b.label)"))
                        .foregroundStyle(color(b.setting).opacity(0.12))
                    if showInner {
                        AreaMark(x: .value("G", b.games),
                                 yStart: .value("下位25%", b.p25),
                                 yEnd: .value("上位25%", b.p75),
                                 series: .value("帯", "50-\(b.label)"))
                            .foregroundStyle(color(b.setting).opacity(0.22))
                    }
                    LineMark(x: .value("G", b.games), y: .value("中央値", b.p50),
                             series: .value("設定", b.label))
                        .foregroundStyle(color(b.setting))
                }
                RuleMark(y: .value("0", 0)).foregroundStyle(.secondary.opacity(0.5))
            }
            .chartXAxisLabel("ゲーム数")
            .chartYAxisLabel("差枚")
            .frame(height: 280)
        } header: {
            Text("差枚の揺れ幅")
        } footer: {
            Text("線は中央値、薄い帯は90%の台が収まる範囲、濃い帯は50%の範囲です。帯が重なっている区間は、グラフの形だけでは設定を見分けにくい区間です。")
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

    private func color(_ i: Int) -> Color {
        let palette: [Color] = [.blue, .teal, .green, .yellow, .orange, .red]
        return palette[i % palette.count]
    }
}
