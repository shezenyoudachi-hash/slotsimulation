import Foundation
import Observation

/// 実戦中の当たり1回分。gap はデータカウンターの「スタート」（前の当たりからのゲーム数）
struct HitEvent: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case big, reg }
    var id = UUID()
    var kind: Kind
    var gap: Int
    /// この当たりまでに数えたぶどう（前の当たり〜この当たり、自分が打った分）
    var grapes = 0
    var time = Date()
}

/// 1台分の実戦記録。着席時のカウンターの数字から始めて、当たりを順に足していく
struct PlaySession: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var unit: Int?

    /// 着席時のデータカウンター（総回転・BIG・REG・スタート）
    var startTotal = 0
    var startBig = 0
    var startReg = 0
    var startGap = 0

    var hits: [HitEvent] = []
    /// 最後の当たりのあとに数えているぶどう
    var pendingGrapes = 0
    /// やめた時のスタート（nil なら打っている途中）
    var endGap: Int?
    var memo = ""

    var isEnded: Bool { endGap != nil }
    var bigCount: Int { startBig + hits.filter { $0.kind == .big }.count }
    var regCount: Int { startReg + hits.filter { $0.kind == .reg }.count }
    var myBig: Int { hits.filter { $0.kind == .big }.count }
    var myReg: Int { hits.filter { $0.kind == .reg }.count }

    /// 最後に分かっている時点（最後の当たり、やめた時点）までに自分が回したゲーム数
    var myGames: Int {
        var g = 0
        for (i, h) in hits.enumerated() { g += (i == 0) ? max(h.gap - startGap, 0) : h.gap }
        if let e = endGap { g += hits.isEmpty ? max(e - startGap, 0) : e }
        return g
    }

    /// 台の総回転（最後に分かっている時点まで）
    var totalGames: Int { startTotal + myGames }

    /// ぶどうを数えた区間（当たりまで確定した区間だけ）のゲーム数と個数
    var grapeStats: (games: Int, count: Int) {
        var g = 0
        var c = 0
        for (i, h) in hits.enumerated() {
            g += (i == 0) ? max(h.gap - startGap, 0) : h.gap
            c += h.grapes
        }
        if let e = endGap {
            g += hits.isEmpty ? max(e - startGap, 0) : e
            c += pendingGrapes
        }
        return (g, c)
    }
    var totalGrapes: Int { hits.reduce(0) { $0 + $1.grapes } + pendingGrapes }

    /// 自分が打った区間の差枚（概算）。小役の払い出しは機械割から逆算した平均を使う
    func estimatedDiff(spec: MachineSpec, settingWeights: [Double]) -> Int {
        var perGame = 0.0
        for i in settingWeights.indices where i < spec.payoutRates.count {
            let base: Double = spec.bet * spec.payoutRates[i] / 100
                - spec.bigPayout / spec.bigDenoms[i] - spec.regPayout / spec.regDenoms[i] - spec.bet
            perGame += settingWeights[i] * base
        }
        let bonus: Double = spec.bigPayout * Double(myBig) + spec.regPayout * Double(myReg)
        return Int((Double(myGames) * perGame + bonus).rounded())
    }

    /// 検証タブ用：着席時を「途中」、やめた時を「最終」にする
    func validationRecord() -> ValidationRecord? {
        guard isEnded else { return nil }
        var r = ValidationRecord()
        r.date = date
        r.unit = unit
        r.checkGames = startTotal
        r.checkBig = startBig
        r.checkReg = startReg
        r.finalGames = totalGames
        r.finalBig = bigCount
        r.finalReg = regCount
        r.memo = "記録タブから追加"
        return r
    }

    /// これまで手で書いていたメモと同じ形式
    func memoText() -> String {
        var lines: [String] = []
        if let u = unit { lines.append("\(u)") }
        lines.append("\(startTotal)/\(startBig)/\(startReg)")
        lines.append("\(startGap)-")
        for h in hits { lines.append("\(h.gap) \(h.kind == .big ? "b" : "r")") }
        if let e = endGap {
            lines.append("\(e) やめ")
            lines.append("\(totalGames)/\(bigCount)/\(regCount)")
        }
        if totalGrapes > 0 { lines.append("ぶどう \(totalGrapes)") }
        return lines.joined(separator: "\n")
    }
}

/// 実戦記録を端末内に JSON で保存する
@Observable
@MainActor
final class PlayStore {
    private(set) var sessions: [PlaySession] = []

    private let fileURL: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("play-sessions.json")

    init() { load() }

    /// 打っている途中の記録（1つだけ）
    var active: PlaySession? { sessions.first { !$0.isEnded } }

    func upsert(_ s: PlaySession) {
        if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.insert(s, at: 0) }
        save()
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        sessions = (try? dec.decode([PlaySession].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(sessions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
