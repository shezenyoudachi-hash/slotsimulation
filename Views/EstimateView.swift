import SwiftUI
import Charts

/// BIG/REG 回数からの設定推測（ベイズ推定）
struct EstimateView: View {
    @Environment(BankStore.self) private var store
    @State private var games = 3000
    @State private var big = 12
    @State private var reg = 10

    private var result: EstimateResult {
        SettingEstimator.estimate(machine: store.spec, games: games,
                                  counts: ["BIG": big, "REG": reg])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("実戦データ") {
                    IntField(title: "総ゲーム数", value: $games)
                    IntField(title: "BIG", value: $big)
                    IntField(title: "REG", value: $reg)
                    if games > 0 {
                        LabeledContent("BIG確率", value: Fmt.denom(big > 0 ? Double(games) / Double(big) : .infinity))
                        LabeledContent("REG確率", value: Fmt.denom(reg > 0 ? Double(games) / Double(reg) : .infinity))
                        LabeledContent("合算", value: Fmt.denom(big + reg > 0 ? Double(games) / Double(big + reg) : .infinity))
                    }
                }

                Section {
                    let r = result
                    Chart(Array(r.labels.enumerated()), id: \.offset) { item in
                        BarMark(x: .value("設定", "設定\(item.element)"),
                                y: .value("確率", r.posteriors[item.offset]))
                            .foregroundStyle(item.offset >= store.spec.highFromIndex ? Color.orange : Color.blue)
                            .annotation(position: .top) {
                                Text(Fmt.pct(r.posteriors[item.offset])).font(.caption2)
                            }
                    }
                    .chartYScale(domain: 0...1)
                    .frame(height: 220)
                    LabeledContent("設定4以上の確率", value: Fmt.pct(r.highProb))
                    LabeledContent("設定の期待値", value: String(format: "%.2f", r.expectedSetting))
                } header: {
                    Text("推測結果")
                } footer: {
                    Text("各設定が同じ割合で使われている前提での確率です。ボーナス確率だけからの推測なので、数千G程度では大きく外れることがあります（揺れ分析タブで的中率を確認できます）。")
                }

                Section("スペック（\(store.spec.name)）") {
                    ForEach(store.spec.labels.indices, id: \.self) { i in
                        HStack {
                            Text("設定\(store.spec.labels[i])").frame(width: 56, alignment: .leading)
                            Text("B \(Fmt.denom(store.spec.bigDenoms[i]))")
                            Spacer()
                            Text("R \(Fmt.denom(store.spec.regDenoms[i]))")
                            Spacer()
                            Text(String(format: "%.1f%%", store.spec.payoutRates[i]))
                        }
                        .font(.footnote.monospacedDigit())
                    }
                }
            }
            .navigationTitle("設定推測")
        }
    }
}
