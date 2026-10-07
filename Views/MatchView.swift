import SwiftUI
import Charts

/// 実際のスランプグラフに似たシミュレーションを探し、設定と今後の動きを同定する
struct MatchView: View {
    @Environment(BankStore.self) private var store

    @State private var currentGames = 1000
    @State private var currentDiff = -300
    @State private var useBonus = true
    @State private var big = 3
    @State private var reg = 2
    @State private var pastPoints: [ObservedPoint] = []
    @State private var showTrace = false
    @State private var horizonAdd = 2000
    @State private var neighbors = 300
    @State private var result: MatchResult?

    var body: some View {
        NavigationStack {
            Form {
                BankControlSection()

                Section("現在の状況") {
                    IntField(title: "現在のゲーム数", value: $currentGames)
                    IntField(title: "現在の差枚", value: $currentDiff)
                    Toggle("ボーナス回数も比べる", isOn: $useBonus)
                    if useBonus {
                        IntField(title: "BIG", value: $big)
                        IntField(title: "REG", value: $reg)
                    }
                }

                Section {
                    Button {
                        showTrace = true
                    } label: {
                        Label("グラフをなぞって入力", systemImage: "hand.draw")
                    }
                    .disabled(currentGames <= 0)

                    if !pastPoints.isEmpty {
                        LabeledContent("取り込み済み", value: "\(pastPoints.count)点")
                        DisclosureGroup("点を個別に直す") {
                            ForEach($pastPoints) { $p in
                                HStack {
                                    TextField("G", value: $p.games, format: .number)
                                        .keyboardType(.numberPad)
                                    Text("G").foregroundStyle(.secondary)
                                    TextField("差枚", value: $p.diff, format: .number)
                                        .keyboardType(.numbersAndPunctuation)
                                        .multilineTextAlignment(.trailing)
                                    Text("枚").foregroundStyle(.secondary)
                                }
                            }
                            .onDelete { pastPoints.remove(atOffsets: $0) }
                        }
                        Button("途中経過を消す", role: .destructive) { pastPoints = [] }
                    }
                } header: {
                    Text("途中経過（任意）")
                } footer: {
                    Text("先に「現在のゲーム数」を入れてから、データカウンターのグラフの写真をなぞってください。現在の差枚も自動で入ります。")
                }

                Section("同定の条件") {
                    Picker("予測する先", selection: $horizonAdd) {
                        ForEach([500, 1000, 2000, 4000], id: \.self) { Text("あと\($0)G").tag($0) }
                    }
                    Picker("類似グラフの本数", selection: $neighbors) {
                        ForEach([100, 300, 1000], id: \.self) { Text("\($0)本").tag($0) }
                    }
                    Button("類似グラフを探す") { runMatch() }
                        .disabled(store.bank == nil || store.isRunning)
                }

                if let r = result {
                    resultSections(r)
                }
            }
            .navigationTitle("類似グラフ同定")
            .sheet(isPresented: $showTrace) {
                GraphTraceView(currentGames: currentGames) { points, diff in
                    pastPoints = points
                    currentDiff = diff
                    result = nil
                }
            }
        }
    }

    private func runMatch() {
        guard let bank = store.bank else { return }
        let q = MatchQuery(currentGames: currentGames, currentDiff: currentDiff,
                           pastPoints: pastPoints,
                           big: useBonus ? big : nil, reg: useBonus ? reg : nil,
                           horizonGames: currentGames + horizonAdd,
                           neighbors: neighbors)
        result = bank.match(q)
    }

    @ViewBuilder
    private func resultSections(_ r: MatchResult) -> some View {
        Section {
            Chart {
                ForEach(r.fan) { f in
                    AreaMark(x: .value("G", f.games), yStart: .value("5%", f.p5), yEnd: .value("95%", f.p95),
                             series: .value("帯", "90"))
                        .foregroundStyle(.orange.opacity(0.15))
                    AreaMark(x: .value("G", f.games), yStart: .value("25%", f.p25), yEnd: .value("75%", f.p75),
                             series: .value("帯", "50"))
                        .foregroundStyle(.orange.opacity(0.3))
                    LineMark(x: .value("G", f.games), y: .value("中央値", f.p50), series: .value("線", "中央値"))
                        .foregroundStyle(.orange)
                    LineMark(x: .value("G", f.games), y: .value("理論値", f.theory), series: .value("線", "理論値"))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                ForEach(r.closestPaths) { p in
                    LineMark(x: .value("G", p.games), y: .value("差枚", p.diff), series: .value("類似", "s\(p.path)"))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 0.8))
                }
                ForEach(r.observed) { o in
                    LineMark(x: .value("G", o.games), y: .value("差枚", o.diff), series: .value("線", "実戦"))
                        .foregroundStyle(.red)
                    PointMark(x: .value("G", o.games), y: .value("差枚", o.diff))
                        .foregroundStyle(.red)
                }
                RuleMark(x: .value("現在", r.currentGames))
                    .foregroundStyle(.red.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            .chartXAxisLabel("ゲーム数")
            .chartYAxisLabel("差枚")
            .frame(height: 300)
        } header: {
            Text("今後の動き")
        } footer: {
            Text("赤：入力したグラフ／灰：特に似ていたシミュレーション\(min(15, r.usedNeighbors))本／橙：似ていた\(r.usedNeighbors)本のその後（濃い帯50%・薄い帯90%）／点線：理論値")
        }

        Section("あと\(r.horizonGames - r.currentGames)Gの予測") {
            LabeledContent("増減の中央値", value: Fmt.signed(r.gainMedian) + "枚")
            LabeledContent("増減の平均", value: Fmt.signed(r.gainMean) + "枚")
            LabeledContent("理論値", value: Fmt.signed(r.theoryGain) + "枚")
            LabeledContent("差枚が増える確率", value: Fmt.pct(r.gainUpRate))
            if let lo = r.fan.last?.p5, let hi = r.fan.last?.p95 {
                LabeledContent("90%の範囲", value: "\(Fmt.signed(lo)) 〜 \(Fmt.signed(hi))")
            }
        }

        Section {
            Chart {
                ForEach(Array(r.labels.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("設定", "設定\(item.element)"),
                            y: .value("割合", r.settingShares[item.offset]))
                        .foregroundStyle(by: .value("根拠", "グラフ形状"))
                        .position(by: .value("根拠", "グラフ形状"))
                    if let b = r.bayes {
                        BarMark(x: .value("設定", "設定\(item.element)"),
                                y: .value("割合", b.posteriors[item.offset]))
                            .foregroundStyle(by: .value("根拠", "ボーナス確率"))
                            .position(by: .value("根拠", "ボーナス確率"))
                    }
                }
            }
            .chartYScale(domain: 0...1)
            .frame(height: 200)
            LabeledContent("設定4以上（グラフ形状）", value: Fmt.pct(r.highShare))
            if let b = r.bayes {
                LabeledContent("設定4以上（ボーナス確率）", value: Fmt.pct(b.highProb))
            }
        } header: {
            Text("同定された設定")
        } footer: {
            Text("似ていたシミュレーションが、どの設定から生まれたものかの割合です。各ゲームの抽選は独立なので、今後の動きはこの設定の割合と機械割でほぼ決まり、過去の波の形そのものが続くわけではありません。中央値が点線（理論値）とほぼ重なるのはそのためです。")
        }
    }
}
