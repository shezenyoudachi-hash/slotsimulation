import SwiftUI

/// 実戦中の当たりを記録する画面。上に YouTube（任意）、下に記録
struct RecordView: View {
    @Environment(BankStore.self) private var bankStore
    @Environment(PlayStore.self) private var playStore
    @Environment(ValidationStore.self) private var validationStore

    @AppStorage("record.youtubeURL") private var youtubeURL = ""
    @AppStorage("record.showPlayer") private var showPlayer = true
    @State private var editingURL = false
    @State private var urlDraft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showPlayer, let path = YouTubeLink.embedPath(from: youtubeURL) {
                    YouTubePlayerView(embedPath: path)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                }
                if let s = playStore.active {
                    ActiveSessionForm(session: s)
                } else {
                    StartSessionForm()
                }
            }
            .navigationTitle("記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { urlDraft = youtubeURL; editingURL = true } label: {
                        Label("YouTube", systemImage: "play.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if YouTubeLink.embedPath(from: youtubeURL) != nil {
                        Button(showPlayer ? "隠す" : "表示") { showPlayer.toggle() }
                    }
                }
            }
            .alert("YouTube の URL", isPresented: $editingURL) {
                TextField("https://www.youtube.com/watch?v=…", text: $urlDraft)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("決定") { youtubeURL = urlDraft; showPlayer = true }
                Button("消す", role: .destructive) { youtubeURL = "" }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("動画・ライブ・再生リストの URL を貼り付けてください。")
            }
        }
    }
}

// MARK: - 着席

private struct StartSessionForm: View {
    @Environment(PlayStore.self) private var playStore

    @State private var unit: Int?
    @State private var total: Int?
    @State private var big: Int?
    @State private var reg: Int?
    @State private var gap: Int?

    var body: some View {
        Form {
            Section {
                numberRow("台番（任意）", $unit)
                numberRow("総回転", $total)
                numberRow("BIG", $big)
                numberRow("REG", $reg)
                numberRow("スタート（今のハマり）", $gap)
                Button("記録を始める") {
                    var s = PlaySession()
                    s.unit = unit
                    s.startTotal = total ?? 0
                    s.startBig = big ?? 0
                    s.startReg = reg ?? 0
                    s.startGap = gap ?? 0
                    playStore.upsert(s)
                }
                .disabled(total == nil)
            } header: {
                Text("座った時のデータカウンター")
            } footer: {
                Text("0Gから打つときは、総回転・BIG・REG・スタートをすべて0にします。")
            }
            HistorySection()
        }
    }

    private func numberRow(_ title: String, _ value: Binding<Int?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }
}

// MARK: - 打っている途中

private struct ActiveSessionForm: View {
    @Environment(BankStore.self) private var bankStore
    @Environment(PlayStore.self) private var playStore
    @Environment(ValidationStore.self) private var validationStore

    let session: PlaySession
    @State private var gapInput: Int?
    @State private var askEnd = false
    @State private var endGapText = ""
    @FocusState private var focused: Bool

    private var estimate: EstimateResult {
        SettingEstimator.estimate(machine: bankStore.spec, games: session.totalGames,
                                  counts: ["BIG": session.bigCount, "REG": session.regCount])
    }

    var body: some View {
        Form {
            statusSection
            hitSection
            grapeSection
            Section("当たり（新しい順）") {
                ForEach(Array(session.hits.enumerated().reversed()), id: \.element.id) { item in
                    HStack {
                        Text(item.element.kind == .big ? "BIG" : "REG")
                            .bold()
                            .foregroundStyle(item.element.kind == .big ? Color.red : Color.blue)
                            .frame(width: 44, alignment: .leading)
                        Text("\(item.element.gap)G")
                        Spacer()
                        if item.element.grapes > 0 { Text("ぶどう \(item.element.grapes)").foregroundStyle(.secondary) }
                        Text(item.element.time, format: .dateTime.hour().minute()).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    var s = session
                    // 表示は新しい順なので、元の並びの位置に直して消す
                    let idx = offsets.map { s.hits.count - 1 - $0 }
                    for i in idx.sorted(by: >) { s.hits.remove(at: i) }
                    playStore.upsert(s)
                }
                Text("着席時：\(session.startTotal)G・BIG \(session.startBig)・REG \(session.startReg)・スタート \(session.startGap)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("やめる（最後のスタートを入力）") { endGapText = ""; askEnd = true }
                    .foregroundStyle(.orange)
            }
        }
        .alert("やめた時のスタート", isPresented: $askEnd) {
            TextField("例：60", text: $endGapText).keyboardType(.numberPad)
            Button("記録を終える") {
                var s = session
                s.endGap = Int(endGapText.trimmingCharacters(in: .whitespaces)) ?? 0
                playStore.upsert(s)
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private var statusSection: some View {
        Section {
            let e = estimate
            let g = max(session.totalGames, 1)
            LabeledContent("自分が回した", value: "\(session.myGames)G")
            LabeledContent("台の総回転", value: "\(session.totalGames)G")
            LabeledContent("BIG", value: "\(session.bigCount)回（1/\(session.bigCount > 0 ? g / session.bigCount : 0)）")
            LabeledContent("REG", value: "\(session.regCount)回（1/\(session.regCount > 0 ? g / session.regCount : 0)）")
            LabeledContent("設定4以上", value: String(format: "%.0f%%", e.highProb * 100))
            LabeledContent("差枚（自分の区間・概算）",
                           value: "\(session.estimatedDiff(spec: bankStore.spec, settingWeights: e.posteriors))枚")
        } header: {
            Text(session.unit.map { "\($0)番台" } ?? "今の台")
        } footer: {
            Text("ゲーム数は最後の当たりまで。差枚は小役の払い出しを機械割からの平均で計算した概算です。")
        }
    }

    private var hitSection: some View {
        Section("当たりを記録") {
            HStack {
                Text("スタート")
                TextField("当たった時の数字", value: $gapInput, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
            }
            HStack(spacing: 12) {
                hitButton("BIG", .big, .red)
                hitButton("REG", .reg, .blue)
            }
            .buttonStyle(.plain)
        }
    }

    private func hitButton(_ title: String, _ kind: HitEvent.Kind, _ color: Color) -> some View {
        Button {
            guard let gap = gapInput else { return }
            var s = session
            s.hits.append(HitEvent(kind: kind, gap: gap, grapes: s.pendingGrapes))
            s.pendingGrapes = 0
            playStore.upsert(s)
            gapInput = nil
            focused = false
        } label: {
            Text(title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(color.opacity(gapInput == nil ? 0.25 : 0.9), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
        .disabled(gapInput == nil)
    }

    private var grapeSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    var s = session
                    s.pendingGrapes += 1
                    playStore.upsert(s)
                } label: {
                    Text("ぶどう +1　（\(session.totalGrapes)）")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.green.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                Button {
                    var s = session
                    s.pendingGrapes = max(s.pendingGrapes - 1, 0)
                    playStore.upsert(s)
                } label: {
                    Text("−1").frame(width: 56, height: 52)
                        .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .buttonStyle(.plain)
            let st = session.grapeStats
            if st.games > 0 && st.count > 0 {
                LabeledContent("ぶどう確率（当たりまで確定した区間）",
                               value: String(format: "1/%.2f", Double(st.games) / Double(st.count)))
            }
        } header: {
            Text("ぶどう")
        } footer: {
            Text("ぶどうの確率はメーカーの公表値がないため、設定推測には使いません。記録と動画のネタ用です。")
        }
    }
}

// MARK: - 過去の記録

private struct HistorySection: View {
    @Environment(PlayStore.self) private var playStore

    var body: some View {
        let ended = playStore.sessions.filter(\.isEnded)
        if !ended.isEmpty {
            Section("過去の記録") {
                ForEach(ended) { s in
                    NavigationLink {
                        SessionDetailView(sessionID: s.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(s.date, format: .dateTime.year().month().day())
                            Text("\(s.unit.map { "\($0)番台・" } ?? "")\(s.totalGames)G・BIG \(s.bigCount)・REG \(s.regCount)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct SessionDetailView: View {
    @Environment(BankStore.self) private var bankStore
    @Environment(PlayStore.self) private var playStore
    @Environment(ValidationStore.self) private var validationStore
    @Environment(\.dismiss) private var dismiss

    let sessionID: UUID
    @State private var added = false
    @State private var confirmDelete = false

    var body: some View {
        if let s = playStore.sessions.first(where: { $0.id == sessionID }) {
            let e = SettingEstimator.estimate(machine: bankStore.spec, games: s.totalGames,
                                              counts: ["BIG": s.bigCount, "REG": s.regCount])
            Form {
                Section("結果") {
                    LabeledContent("自分が回した", value: "\(s.myGames)G（BIG \(s.myBig)・REG \(s.myReg)）")
                    LabeledContent("台の総回転", value: "\(s.totalGames)G（BIG \(s.bigCount)・REG \(s.regCount)）")
                    LabeledContent("設定4以上", value: String(format: "%.0f%%", e.highProb * 100))
                    LabeledContent("差枚（概算）", value: "\(s.estimatedDiff(spec: bankStore.spec, settingWeights: e.posteriors))枚")
                    if s.totalGrapes > 0 {
                        LabeledContent("ぶどう", value: "\(s.totalGrapes)個")
                    }
                }
                Section("メモ（これまでの書き方）") {
                    Text(s.memoText()).font(.system(.body, design: .monospaced))
                    ShareLink(item: s.memoText()) { Label("メモを共有・コピー", systemImage: "square.and.arrow.up") }
                }
                Section {
                    Button(added ? "検証タブに追加しました" : "検証タブに追加（着席時→やめた時）") {
                        if let r = s.validationRecord() { validationStore.append([r]); added = true }
                    }
                    .disabled(added)
                    Button("この記録を削除", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(Text(s.date, format: .dateTime.month().day()))
            .confirmationDialog("この記録を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) { playStore.delete(sessionID); dismiss() }
            }
        } else {
            Text("記録が見つかりません")
        }
    }
}
