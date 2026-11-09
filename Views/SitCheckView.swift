import SwiftUI
import Charts

/// 空いている台のデータカウンターを入れて「座っていいか」を判定する
struct SitCheckView: View {
    @Environment(BankStore.self) private var store
    @AppStorage("sit.games") private var games = 2000
    @AppStorage("sit.big") private var big = 8
    @AppStorage("sit.reg") private var reg = 8
    @AppStorage("sit.hall") private var hallRaw = SitAdvisor.Hall.normal.rawValue
    @AppStorage("sit.playMode") private var playMode = 0   // 0: 閉店まで 1: 2000G 2: 自分で入力
    @AppStorage("sit.playGames") private var customPlay = 2000
    @AppStorage("sit.closeGames") private var closeGames = 8000
    @State private var showTable = false

    private var hall: SitAdvisor.Hall { SitAdvisor.Hall(rawValue: hallRaw) ?? .normal }

    private var playGames: Int {
        switch playMode {
        case 1: 2000
        case 2: max(customPlay, 0)
        default: max(closeGames - games, 0)
        }
    }

    private var advice: SitAdvisor.Advice {
        SitAdvisor.advise(spec: store.spec, games: games, big: big, reg: reg,
                          hall: hall, playGames: playGames)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    IntField(title: "総回転", value: $games)
                    IntField(title: "BIG", value: $big)
                    IntField(title: "REG", value: $reg)
                    if games > 0 {
                        HStack {
                            Text("BIG \(Fmt.denom(big > 0 ? Double(games) / Double(big) : .infinity))")
                            Spacer()
                            Text("REG \(Fmt.denom(reg > 0 ? Double(games) / Double(reg) : .infinity))")
                            Spacer()
                            Text("合算 \(Fmt.denom(big + reg > 0 ? Double(games) / Double(big + reg) : .infinity))")
                        }
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("空いている台のデータカウンター")
                }

                Section {
                    Picker("店", selection: $hallRaw) {
                        ForEach(SitAdvisor.Hall.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Picker("これから打つ", selection: $playMode) {
                        Text("閉店まで").tag(0)
                        Text("2000G").tag(1)
                        Text("自分で入力").tag(2)
                    }
                    if playMode == 0 {
                        IntField(title: "閉店までの総回転（目安）", value: $closeGames)
                    } else if playMode == 2 {
                        IntField(title: "打つゲーム数", value: $customPlay)
                    }
                } header: {
                    Text("条件")
                } footer: {
                    Text(hall.note)
                }

                verdictSection

                Section {
                    let r = advice.estimate
                    Chart(Array(r.labels.enumerated()), id: \.offset) { item in
                        BarMark(x: .value("設定", "設定\(item.element)"),
                                y: .value("確率", r.posteriors[item.offset]))
                            .foregroundStyle(item.offset >= store.spec.highFromIndex ? Color.orange : Color.blue)
                            .annotation(position: .top) {
                                Text(Fmt.pct(r.posteriors[item.offset])).font(.caption2)
                            }
                    }
                    .chartYScale(domain: 0...1)
                    .frame(height: 180)
                    LabeledContent("設定4以上の確率", value: Fmt.pct(r.highProb))
                } header: {
                    Text("設定の確率（\(hall.rawValue)）")
                }

                Section {
                    DisclosureGroup("早見表（\(hall.rawValue)）", isExpanded: $showTable) {
                        ForEach(SitAdvisor.table(spec: store.spec, hall: hall)) { row in
                            HStack {
                                Text("\(row.games)G").frame(width: 64, alignment: .leading)
                                Spacer()
                                if let r = row.reg {
                                    Text("REG \(r)回以上")
                                    Text("(\(Fmt.denom(Double(row.games) / Double(max(r, 1)))))")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("—")
                                }
                            }
                            .font(.subheadline.monospacedDigit())
                        }
                    }
                } footer: {
                    Text("BIGがその回転数で平均的な回数のときの目安です。")
                }

                Section {
                    Text("メーカー公表のBIG・REG確率と機械割だけで計算しています（小役は機械割からの平均）。店の設定配分は選んだ仮定です。座ったあとは、2000Gから1000Gごとに設定推測を見て、設定4以上が30%を切ったらやめるのが目安です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("座る？")
        }
    }

    @ViewBuilder private var verdictSection: some View {
        let a = advice
        Section {
            VStack(spacing: 8) {
                Text(a.sitOK ? "座ってOK" : "見送り")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(a.sitOK ? Color.orange : Color.secondary)
                Text("\(playGames)G打つと 平均 \(Fmt.signed(a.expectedDiff))枚")
                    .font(.headline.monospacedDigit())
                Text("1000Gあたり \(Fmt.signed(a.per1000))枚")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentTransition(.numericText())
            .animation(.default, value: a.sitOK)

            if let need = a.regNeeded {
                if a.sitOK {
                    LabeledContent("この回転数の基準", value: "REG \(need)回以上")
                } else {
                    LabeledContent("座ってOKまで", value: "REG あと\(max(need - reg, 0))回（\(need)回）")
                }
            } else {
                LabeledContent("座ってOKまで", value: "この回転数では届きません")
            }
        } header: {
            Text("判定")
        }
    }
}
