import Foundation

/// 実戦記録をアプリの外（「ファイル」アプリ・iCloud Drive）に書き出す。
/// 1回の実戦 = 1つの JSON。あとで Claude などに読ませやすいよう、
/// 生の当たり履歴と、そこから計算した値の両方を入れる。
enum SessionExporter {
    /// 書き出す JSON の形
    struct Exported: Encodable {
        struct Counter: Encodable {
            var totalGames: Int
            var big: Int
            var reg: Int
            /// データカウンターの「スタート」（前の当たりからのゲーム数）
            var gap: Int
        }
        struct Hit: Encodable {
            var no: Int
            var kind: String
            /// 当たった時のスタート（前の当たりからのゲーム数）
            var gap: Int
            /// この当たりの時点での台の総回転
            var totalGamesAtHit: Int
            /// 前の当たり〜この当たりで数えたぶどう（自分が打った分）
            var grapes: Int
            var time: Date
        }
        struct Mine: Encodable {
            var games: Int
            var big: Int
            var reg: Int
            var grapes: Int
            /// ぶどうを数えた区間（当たり・やめで確定した区間）のゲーム数と個数
            var grapeGames: Int
            var grapeCount: Int
        }
        struct Estimate: Encodable {
            /// 設定ごとの確率（事前分布は一様。メーカー公表の BIG/REG 確率だけで計算）
            var settingProbabilities: [String: Double]
            var setting4OrHigher: Double
            /// 自分が打った区間の差枚の概算（小役の払い出しは機械割から逆算した平均）
            var estimatedDiffCoins: Int
            var basis: String
        }

        var format = "SlotAnalyzer 実戦記録 v1"
        var exportedAt: Date
        var id: UUID
        var machine: String
        var unit: Int?
        var startedAt: Date
        var endedAt: Date?
        /// 座った時のデータカウンター
        var atStart: Counter
        /// やめた時（推定）のデータカウンター
        var atEnd: Counter?
        var mine: Mine
        var hits: [Hit]
        var estimate: Estimate
        /// これまで手で書いていたメモと同じ形式
        var memoText: String
        var note: String
    }

    static func make(_ s: PlaySession, spec: MachineSpec) -> Exported {
        var total = s.startTotal
        var hits: [Exported.Hit] = []
        for (i, h) in s.hits.enumerated() {
            total += (i == 0) ? max(h.gap - s.startGap, 0) : h.gap
            hits.append(.init(no: i + 1, kind: h.kind == .big ? "BIG" : "REG", gap: h.gap,
                              totalGamesAtHit: total, grapes: h.grapes, time: h.time))
        }
        let e = SettingEstimator.estimate(machine: spec, games: s.totalGames,
                                          counts: ["BIG": s.bigCount, "REG": s.regCount])
        var probs: [String: Double] = [:]
        for (i, p) in e.posteriors.enumerated() where i < spec.labels.count {
            probs["設定" + spec.labels[i]] = (p * 10000).rounded() / 10000
        }
        let st = s.grapeStats
        return Exported(
            exportedAt: Date(), id: s.id,
            machine: s.machine ?? spec.name, unit: s.unit,
            startedAt: s.date, endedAt: s.endedAt,
            atStart: .init(totalGames: s.startTotal, big: s.startBig, reg: s.startReg, gap: s.startGap),
            atEnd: s.endGap.map { .init(totalGames: s.totalGames, big: s.bigCount, reg: s.regCount, gap: $0) },
            mine: .init(games: s.myGames, big: s.myBig, reg: s.myReg, grapes: s.totalGrapes,
                        grapeGames: st.games, grapeCount: st.count),
            hits: hits,
            estimate: .init(settingProbabilities: probs,
                            setting4OrHigher: (e.highProb * 10000).rounded() / 10000,
                            estimatedDiffCoins: s.estimatedDiff(spec: spec, settingWeights: e.posteriors),
                            basis: "台の総回転と BIG・REG 回数（座る前の分も含む）"),
            memoText: s.memoText(),
            note: s.memo)
    }

    static func fileName(_ s: PlaySession) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM-dd_HHmm"
        let unit = s.unit.map { "_\($0)番台" } ?? ""
        return "\(f.string(from: s.date))\(unit).json"
    }

    static func encode(_ x: Exported) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        enc.dateEncodingStrategy = .custom { d, en in
            var c = en.singleValueContainer(); try c.encode(iso.string(from: d))
        }
        return try enc.encode(x)
    }

    // MARK: - 保存先

    /// アプリ内の書き出しフォルダ（「ファイル」アプリ →「このiPhone内」→「SlotAnalyzer」→「実戦記録」）
    static var localFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("実戦記録", isDirectory: true)
    }

    private static let bookmarkKey = "export.folderBookmark"

    /// 自分で選んだ保存先（iCloud Drive のフォルダなど）
    static var chosenFolder: URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale { setChosenFolder(url) }
        return url
    }

    /// フォルダ選択の結果を覚える（次からは自動でそこに保存）
    @discardableResult
    static func setChosenFolder(_ url: URL?) -> Bool {
        guard let url else { UserDefaults.standard.removeObject(forKey: bookmarkKey); return true }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData() else { return false }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        return true
    }

    /// 書き出しの結果
    struct Result {
        var savedLocal = false
        var savedChosen = false
        var error: String?
    }

    /// 1回分を書き出す。アプリ内フォルダには必ず、選んだフォルダがあればそこにも保存
    @discardableResult
    static func export(_ s: PlaySession, spec: MachineSpec) -> Result {
        var r = Result()
        let name = fileName(s)
        let data: Data
        do { data = try encode(make(s, spec: spec)) } catch {
            r.error = "書き出しに失敗しました：\(error.localizedDescription)"; return r
        }
        do {
            try write(data, readme: true, to: localFolder, name: name)
            r.savedLocal = true
        } catch { r.error = "アプリ内への保存に失敗しました：\(error.localizedDescription)" }

        if let folder = chosenFolder {
            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }
            var coordError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordError) { dir in
                do { try write(data, readme: true, to: dir, name: name) } catch { writeError = error }
            }
            if let e = writeError ?? coordError {
                r.error = "選んだフォルダへの保存に失敗しました（フォルダを選び直してください）：\(e.localizedDescription)"
            } else {
                r.savedChosen = true
            }
        }
        return r
    }

    private static func write(_ data: Data, readme: Bool, to dir: URL, name: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        let readmeURL = dir.appendingPathComponent("README.md")
        if readme, !fm.fileExists(atPath: readmeURL.path) {
            try? readmeText.data(using: .utf8)?.write(to: readmeURL, options: .atomic)
        }
    }

    /// フォルダに置く説明（Claude などがファイルの読み方を分かるように）
    static let readmeText = """
    # SlotAnalyzer 実戦記録

    1回の実戦（1台）につき1つの JSON。ファイル名は「着席日時_台番.json」。
    記録を終えた時に自動で書き出され、同じ記録を書き出し直すと上書きされる。

    ## 項目
    - machine: 機種名
    - unit: 台番（任意）
    - startedAt / endedAt: 記録を始めた時刻 / やめた時刻
    - atStart: 座った時のデータカウンター（totalGames 総回転, big, reg, gap スタート）
    - atEnd: やめた時のデータカウンター（記録から計算した値）
    - mine: 自分が回した区間（games, big, reg, ぶどう grapes。grapeGames/grapeCount はぶどうを数え終えた区間）
    - hits: 当たりの履歴。gap は当たった時のスタート、totalGamesAtHit はその時点の台の総回転、grapes はその当たりまでに数えたぶどう
    - estimate: 設定推測（メーカー公表の BIG/REG 確率と機械割だけを使ったベイズ推定。事前分布は一様）
      - settingProbabilities: 設定ごとの確率, setting4OrHigher: 設定4以上の確率
      - estimatedDiffCoins: 自分が打った区間の差枚の概算
    - memoText: 手書きメモと同じ形式（台番 / 総回転/BIG/REG / スタート- / 当たり… / やめ / 最終）
    - note: 自由メモ

    ## 注意
    - ゲーム数は当たり・やめの時に入れたスタートから計算している（入力ミスがあればずれる）
    - ぶどうはメーカー公表値がないため、設定推測には使っていない
    - 個人の記録。店名・台番を含むので公開しない
    """
}
