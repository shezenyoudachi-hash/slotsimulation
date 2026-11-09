import Foundation

/// 空いている台に「座っていいか」を判定する。
/// データカウンターの総回転・BIG・REG から設定を推測し（店の設定配分を事前分布にする）、
/// これから打つゲーム数の期待差枚がプラスなら「座ってOK」。
/// 使うのはメーカー公表の BIG/REG 確率と機械割だけ。店の設定配分は利用者が選ぶ仮定。
enum SitAdvisor {
    /// 店の設定配分の仮定（第9〜12話で使ったもの）
    enum Hall: String, CaseIterable, Identifiable {
        case normal = "普通の店"
        case good = "高設定が多い日"
        case uniform = "設定は均等"

        var id: String { rawValue }

        /// 設定1〜6の割合
        var prior: [Double] {
            switch self {
            case .normal: [0.55, 0.20, 0.12, 0.07, 0.03, 0.03]
            case .good: [0.30, 0.15, 0.15, 0.15, 0.10, 0.15]
            case .uniform: Array(repeating: 1.0 / 6, count: 6)
            }
        }

        var note: String {
            switch self {
            case .normal: "設定1が55%・設定6が3%と仮定"
            case .good: "設定1が30%・設定6が15%と仮定"
            case .uniform: "設定1〜6が同じ割合と仮定（アプリの設定推測タブと同じ）"
            }
        }
    }

    struct Advice {
        var estimate: EstimateResult
        /// これから打つゲーム数の期待差枚
        var expectedDiff: Double
        /// 1000Gあたりの期待差枚
        var per1000: Double
        var sitOK: Bool { expectedDiff > 0 }
        /// 今のBIG回数のまま、座ってOKになるREG回数（今の回転数で）
        var regNeeded: Int?
    }

    static func advise(spec: MachineSpec, games: Int, big: Int, reg: Int,
                       hall: Hall, playGames: Int) -> Advice {
        let prior = hall.prior.count == spec.settingCount ? hall.prior : nil
        let e = SettingEstimator.estimate(machine: spec, games: games,
                                          counts: ["BIG": big, "REG": reg], prior: prior)
        let per = perGame(spec: spec, posteriors: e.posteriors)
        return Advice(estimate: e,
                      expectedDiff: per * Double(max(playGames, 0)),
                      per1000: per * 1000,
                      regNeeded: regNeeded(spec: spec, games: games, big: big, hall: hall))
    }

    /// 設定の確率で重みをつけた、1Gあたりの期待差枚
    static func perGame(spec: MachineSpec, posteriors: [Double]) -> Double {
        zip(posteriors, spec.labels.indices).map { $0 * spec.expectedDiffPerGame($1) }.reduce(0, +)
    }

    /// 期待差枚がプラスになる最小のREG回数（ゲーム数に対して現実的な範囲で探す）
    static func regNeeded(spec: MachineSpec, games: Int, big: Int, hall: Hall) -> Int? {
        guard games > 0 else { return nil }
        let prior = hall.prior.count == spec.settingCount ? hall.prior : nil
        let maxReg = max(games / 100, 1)
        for r in 0...maxReg where r + big <= games {
            let e = SettingEstimator.estimate(machine: spec, games: games,
                                              counts: ["BIG": big, "REG": r], prior: prior)
            if perGame(spec: spec, posteriors: e.posteriors) > 0 { return r }
        }
        return nil
    }

    struct TableRow: Identifiable {
        var games: Int
        var big: Int
        var reg: Int?
        var id: Int { games }
    }

    /// 早見表：総回転ごとの「座っていいREG回数」（BIGはその回転数で平均的な回数）
    static func table(spec: MachineSpec, hall: Hall,
                      rows: [Int] = [1000, 2000, 3000, 4000, 5000, 6000]) -> [TableRow] {
        let bigAvg = spec.bigDenoms.reduce(0, +) / Double(spec.bigDenoms.count)
        return rows.map { g in
            let b = Int((Double(g) / bigAvg).rounded())
            return TableRow(games: g, big: b, reg: regNeeded(spec: spec, games: g, big: b, hall: hall))
        }
    }
}
