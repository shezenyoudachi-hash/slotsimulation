import SwiftUI
import UniformTypeIdentifiers

/// 実戦中の当たりを記録する画面。上に YouTube（任意）、下に記録
struct RecordView: View {
    @Environment(BankStore.self) private var bankStore
    @Environment(PlayStore.self) private var playStore
    @Environment(ValidationStore.self) private var validationStore

    @AppStorage("record.youtubeURL") private var youtubeURL = ""
    @AppStorage("record.playerMode") private var playerMode = PlayerMode.app
    @State private var editingURL = false
    @State private var urlDraft = ""
    @Environment(\.openURL) private var openURL

    /// 上半分の使い方
    enum PlayerMode: String, CaseIterable {
        case app      // YouTubeアプリの小窓（ピクチャ・イン・ピクチャ）を置く場所として空ける
        case embed    // アプリ内で再生（ログインなし）
        case off      // 何も表示しない
        var title: String {
            switch self {
            case .app: "YouTubeアプリの小窓を使う"
            case .embed: "アプリ内で再生（ログインなし）"
            case .off: "表示しない"
            }
        }
    }

    var body: some View {
        // 小窓（ピクチャ・イン・ピクチャ）は画面の一番上に吸い付くので、
        // 枠を NavigationStack の外の一番上に置き、タイトルやボタンはその下に出す
        VStack(spacing: 0) {
            switch playerMode {
            case .app:
                PiPSpace { openYouTubeApp() }
            case .embed:
                if let path = YouTubeLink.embedPath(from: youtubeURL) {
                    YouTubePlayerView(embedPath: path)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                }
            case .off:
                EmptyView()
            }
            NavigationStack {
                Group {
                    if let s = playStore.active {
                        ActiveSessionForm(session: s)
                    } else {
                        StartSessionForm()
                    }
                }
                .navigationTitle("記録")
                .navigationBarTitleDisplayMode(.inline)
                .exportAlert(Bindable(playStore).lastExportMessage)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button { openYouTubeApp() } label: {
                                Label("YouTubeアプリを開く", systemImage: "arrow.up.forward.app")
                            }
                            Button { urlDraft = youtubeURL; editingURL = true } label: {
                                Label("動画のURLを設定", systemImage: "link")
                            }
                            Picker("上の部分", selection: $playerMode) {
                                ForEach(PlayerMode.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                        } label: {
                            Label("YouTube", systemImage: "play.rectangle")
                        }
                    }
                }
                .alert("YouTube の URL", isPresented: $editingURL) {
                    TextField("https://www.youtube.com/watch?v=…", text: $urlDraft)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("決定") { youtubeURL = urlDraft }
                    Button("消す", role: .destructive) { youtubeURL = "" }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text("動画・ライブ・再生リストの URL。設定すると「YouTubeアプリを開く」でその動画が開きます。")
                }
            }
        }
    }
}

extension RecordView {
    /// 自分のアカウントでログイン済みの YouTube アプリを開く。URL があればその動画を開く
    func openYouTubeApp() {
        let s = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: s), YouTubeLink.embedPath(from: s) != nil {
            // youtube.com の URL は、YouTube アプリが入っていればアプリで開かれる
            openURL(url)
        } else if let app = URL(string: "youtube://") {
            openURL(app) { ok in
                if !ok, let web = URL(string: "https://m.youtube.com/") { openURL(web) }
            }
        }
    }
}

/// YouTube アプリの小窓（ピクチャ・イン・ピクチャ）を置くための空きスペース
private struct PiPSpace: View {
    let open: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(.secondary)
            .overlay {
                VStack(spacing: 8) {
                    Text("YouTubeの小窓をここに置く")
                        .font(.subheadline.bold())
                    Text("YouTubeアプリで再生 → ホームに戻ると小窓になります")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("YouTubeアプリを開く", action: open)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.horizontal)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

// MARK: - 着席

private struct StartSessionForm: View {
    @Environment(BankStore.self) private var bankStore
    @Environment(PlayStore.self) private var playStore

    @State private var unit: Int?
    @State private var total: Int?
    @State private var big: Int?
    @State private var reg: Int?
    @State private var gap: Int?
    @State private var confirmStart = false

    var body: some View {
        Form {
            Section {
                numberRow("台番（任意）", $unit)
                numberRow("総回転", $total)
                numberRow("BIG", $big)
                numberRow("REG", $reg)
                numberRow("スタート（今のハマり）", $gap)
                Button("記録を始める") { confirmStart = true }
                    .disabled(total == nil)
            } header: {
                Text("座った時のデータカウンター")
            } footer: {
                Text("0Gから打つときは、総回転・BIG・REG・スタートをすべて0にします。")
            }
            HistorySection()
            ExportSettingsSection()
        }
        .alert("この数字で始めますか？", isPresented: $confirmStart) {
            Button("始める") {
                var s = PlaySession()
                s.unit = unit
                s.machine = bankStore.spec.name
                s.startTotal = total ?? 0
                s.startBig = big ?? 0
                s.startReg = reg ?? 0
                s.startGap = gap ?? 0
                playStore.upsert(s)
            }
            Button("直す", role: .cancel) {}
        } message: {
            Text("総回転 \(total ?? 0)G\nBIG \(big ?? 0)回　REG \(reg ?? 0)回\nスタート \(gap ?? 0)G\n\nBIGとREGが逆になっていないか、カウンターと見比べてください。")
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
    @State private var editingStart = false
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
                Button {
                    editingStart = true
                } label: {
                    HStack {
                        Text("着席時：\(session.startTotal)G・BIG \(session.startBig)・REG \(session.startReg)・スタート \(session.startGap)")
                            .font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Text("直す").font(.footnote)
                    }
                }
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
                s.endedAt = Date()
                let r = SessionExporter.export(s, spec: bankStore.spec)
                playStore.lastExportMessage = r.message(fileName: SessionExporter.fileName(s))
                playStore.upsert(s)
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $editingStart) {
            StartEditor(session: session) { playStore.upsert($0) }
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
            GrapeCounter(count: session.totalGrapes) { delta in
                var s = session
                s.pendingGrapes = max(s.pendingGrapes + delta, 0)
                playStore.upsert(s)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            let st = session.grapeStats
            if st.games > 0 && st.count > 0 {
                LabeledContent("ぶどう確率（当たりまで確定した区間）",
                               value: String(format: "1/%.2f", Double(st.games) / Double(st.count)))
            }
        } header: {
            Text("ぶどう")
        } footer: {
            Text("押すと震えてランプが光ります。ぶどうの確率はメーカーの公表値がないため、設定推測には使いません。")
        }
    }
}

/// ぶどうカウンター。押すたびにバイブし、ランプが一瞬光る（カウンター機のような見た目）
private struct GrapeCounter: View {
    let count: Int
    let change: (Int) -> Void
    @State private var lit = false
    @State private var plusTaps = 0
    @State private var minusTaps = 0

    var body: some View {
        HStack(spacing: 12) {
            Button {
                change(1)
                plusTaps += 1
                flash()
            } label: {
                HStack(spacing: 14) {
                    // ランプ
                    Circle()
                        .fill(lit ? Color(red: 0.75, green: 1.0, blue: 0.35) : Color(red: 0.12, green: 0.30, blue: 0.10))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.white.opacity(lit ? 0.9 : 0.25), lineWidth: 2))
                        .shadow(color: Color(red: 0.6, green: 1.0, blue: 0.3).opacity(lit ? 0.95 : 0), radius: lit ? 14 : 0)
                    Text("\(count)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Spacer()
                    Text("ぶどう +1").font(.title3.bold())
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(lit ? Color(red: 0.30, green: 0.75, blue: 0.20) : Color.green.opacity(0.85),
                            in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
                .scaleEffect(lit ? 0.97 : 1)
            }
            .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: plusTaps)

            Button {
                change(-1)
                minusTaps += 1
            } label: {
                Text("−1").font(.headline).frame(width: 56, height: 64)
                    .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
            }
            .sensoryFeedback(.impact(weight: .light), trigger: minusTaps)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: count)
    }

    private func flash() {
        withAnimation(.easeOut(duration: 0.05)) { lit = true }
        let tap = plusTaps
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // 連打中は最後の1回の後に消す
            if tap == plusTaps { withAnimation(.easeIn(duration: 0.3)) { lit = false } }
        }
    }
}

/// 着席時の数字（とやめた時のスタート）を直す画面
private struct StartEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var session: PlaySession
    let save: (PlaySession) -> Void

    init(session: PlaySession, save: @escaping (PlaySession) -> Void) {
        _session = State(initialValue: session)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    row("台番", value: Binding(get: { session.unit ?? 0 }, set: { session.unit = $0 == 0 ? nil : $0 }))
                    row("総回転", value: $session.startTotal)
                    row("BIG", value: $session.startBig)
                    row("REG", value: $session.startReg)
                    row("スタート（今のハマり）", value: $session.startGap)
                    Button("BIGとREGを入れ替える") {
                        let b = session.startBig
                        session.startBig = session.startReg
                        session.startReg = b
                    }
                } header: {
                    Text("座った時のデータカウンター")
                }
                if session.isEnded {
                    Section("やめた時") {
                        row("スタート", value: Binding(get: { session.endGap ?? 0 }, set: { session.endGap = $0 }))
                    }
                }
            }
            .navigationTitle("記録を直す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save(session); dismiss() } }
            }
        }
    }

    private func row(_ title: String, value: Binding<Int>) -> some View {
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
    @State private var exportMessage: String?
    @State private var editing = false

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
                    Button("着席時の数字を直す") { editing = true }
                    Button("ファイルに書き出し直す") {
                        exportMessage = SessionExporter.export(s, spec: bankStore.spec)
                            .message(fileName: SessionExporter.fileName(s))
                    }
                    Button("この記録を削除", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(Text(s.date, format: .dateTime.month().day()))
            .confirmationDialog("この記録を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) { playStore.delete(sessionID); dismiss() }
            }
            .exportAlert($exportMessage)
            .sheet(isPresented: $editing) {
                StartEditor(session: s) { fixed in
                    playStore.upsert(fixed)
                    added = false
                    exportMessage = SessionExporter.export(fixed, spec: bankStore.spec)
                        .message(fileName: SessionExporter.fileName(fixed))
                }
            }
        } else {
            Text("記録が見つかりません")
        }
    }
}

// MARK: - 書き出し

extension SessionExporter.Result {
    func message(fileName: String) -> String {
        var lines: [String] = []
        if savedLocal { lines.append("「ファイル」アプリの SlotAnalyzer ›「実戦記録」に保存しました。") }
        if savedChosen { lines.append("選んだフォルダにも保存しました。") }
        if let error { lines.append(error) }
        lines.append(fileName)
        return lines.joined(separator: "\n")
    }
}

private struct ExportAlert: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("記録の書き出し", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    fileprivate func exportAlert(_ message: Binding<String?>) -> some View {
        modifier(ExportAlert(message: message))
    }
}

/// 書き出し先の設定と、まとめて書き出し
private struct ExportSettingsSection: View {
    @Environment(BankStore.self) private var bankStore
    @Environment(PlayStore.self) private var playStore
    @State private var folderName = SessionExporter.chosenFolder?.lastPathComponent
    @State private var picking = false
    @State private var message: String?

    var body: some View {
        Section {
            LabeledContent("追加の保存先", value: folderName ?? "なし")
            Button(folderName == nil ? "保存先フォルダを選ぶ（iCloud Drive など）" : "保存先フォルダを選び直す") {
                picking = true
            }
            if folderName != nil {
                Button("追加の保存先をやめる", role: .destructive) {
                    SessionExporter.setChosenFolder(nil)
                    folderName = nil
                }
            }
            let ended = playStore.sessions.filter(\.isEnded)
            if !ended.isEmpty {
                Button("これまでの記録をすべて書き出す（\(ended.count)件）") {
                    var ok = 0
                    var err: String?
                    for s in ended {
                        let r = SessionExporter.export(s, spec: bankStore.spec)
                        if r.error == nil { ok += 1 } else { err = r.error }
                    }
                    message = "\(ok)件を書き出しました。" + (err.map { "\n" + $0 } ?? "")
                }
            }
        } header: {
            Text("記録の書き出し")
        } footer: {
            Text("記録を終えると、1回分が JSON ファイルで自動保存されます（「ファイル」アプリの SlotAnalyzer ›「実戦記録」）。iCloud Drive のフォルダを選ぶと、そこにも保存されて Mac から読めます。")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result, SessionExporter.setChosenFolder(url) {
                folderName = url.lastPathComponent
            } else {
                message = "フォルダを選べませんでした。"
            }
        }
        .exportAlert($message)
    }
}
