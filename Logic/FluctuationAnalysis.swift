import Foundation

/// 設定ごとの差枚の帯（スランプグラフの揺れ幅）
struct BandPoint: Identifiable {
    var id: String { "\(setting)-\(games)" }
    var setting: Int
    var label: String
    var games: Int
    var p5: Double
    var p25: Double
    var p50: Double
    var p75: Double
    var p95: Double
    /// 機械割から計算した理論上の期待差枚
    var theory: Double
}

struct SettingSpread: Identifiable {
    var id: Int { setting }
    var setting: Int
    var label: String
    var diffP5: Double
    var diffP50: Double
    var diffP95: Double
    /// 差枚がプラスの割合
    var winRate: Double
    /// ボーナス合算 1/x の 90% 範囲（x の値。運が良い側が小さい）
    var combinedLuckyDenom: Double
    var combinedUnluckyDenom: Double
}

/// ある G 数時点での揺れの大きさと、設定の見分けやすさ
struct CheckpointStat: Identifiable {
    var id: Int { games }
    var games: Int
    var rows: [SettingSpread]
    /// BIG/REG 回数からのベイズ推定で、最も確率が高い設定が本当の設定と一致した割合
    var exactAccuracy: Double
    /// 「高設定（4以上）の確率 > 50%」の判定が本当の高低と一致した割合
    var highLowAccuracy: Double
}

/// グラフの軸の範囲と目盛り
struct AxisScale {
    var domain: ClosedRange<Double>
    var ticks: [Double]

    /// 値の範囲から、切りのいい目盛り（1, 2, 5 × 10^n 刻み）を付けた範囲を作る
    static func nice(min lo: Double, max hi: Double, targetTicks: Int = 6, includeZero: Bool = true) -> AxisScale {
        var lo = lo, hi = hi
        if includeZero { lo = Swift.min(lo, 0); hi = Swift.max(hi, 0) }
        if hi - lo < 1 { lo -= 50; hi += 50 }
        let raw = (hi - lo) / Double(Swift.max(targetTicks - 1, 1))
        let mag = pow(10, floor(log10(raw)))
        let step = [1.0, 2.0, 2.5, 5.0, 10.0].map { $0 * mag }.first { $0 >= raw } ?? 10 * mag
        let start = floor(lo / step) * step
        let end = ceil(hi / step) * step
        let ticks = Array(Swift.stride(from: start, through: end + step * 0.001, by: step))
        return AxisScale(domain: start...end, ticks: ticks)
    }
}

extension SimulationBank {
    static let defaultCheckpoints = [100, 200, 500, 1000, 2000, 4000, 8000]

    /// 差枚の帯を計算する。upToGames を指定するとその G 数までの範囲だけを細かく計算する
    func bands(upToGames: Int? = nil, maxPoints: Int = 60) -> [BandPoint] {
        let last = upToGames.map { index(forGames: $0) } ?? (pointCount - 1)
        let idxs = Stats.thinned(0...max(last, 1), maxPoints: maxPoints)
        var out: [BandPoint] = []
        for s in 0..<spec.settingCount {
            let range = paths(ofSetting: s)
            for i in idxs {
                let sorted = range.map { diffAt($0, i) }.sorted()
                let g = games(atIndex: i)
                out.append(BandPoint(setting: s, label: spec.labels[s], games: g,
                                     p5: Stats.quantile(sorted, 0.05),
                                     p25: Stats.quantile(sorted, 0.25),
                                     p50: Stats.quantile(sorted, 0.5),
                                     p75: Stats.quantile(sorted, 0.75),
                                     p95: Stats.quantile(sorted, 0.95),
                                     theory: spec.expectedDiffPerGame(s) * Double(g)))
            }
        }
        return out
    }

    func checkpointStats(_ checkpoints: [Int] = SimulationBank.defaultCheckpoints) -> [CheckpointStat] {
        checkpoints.filter { $0 > 0 && $0 <= maxGames }.map { g in
            let i = index(forGames: g)
            let realGames = games(atIndex: i)
            var rows: [SettingSpread] = []
            var exactHits = 0
            var hlHits = 0

            for s in 0..<spec.settingCount {
                let range = paths(ofSetting: s)
                let diffs = range.map { diffAt($0, i) }.sorted()
                let combined = range.map { Double(bigAt($0, i) + regAt($0, i)) }.sorted()
                func denom(_ c: Double) -> Double { c > 0 ? Double(realGames) / c : .infinity }
                rows.append(SettingSpread(
                    setting: s, label: spec.labels[s],
                    diffP5: Stats.quantile(diffs, 0.05),
                    diffP50: Stats.quantile(diffs, 0.5),
                    diffP95: Stats.quantile(diffs, 0.95),
                    winRate: Double(diffs.filter { $0 > 0 }.count) / Double(diffs.count),
                    combinedLuckyDenom: denom(Stats.quantile(combined, 0.95)),
                    combinedUnluckyDenom: denom(Stats.quantile(combined, 0.05))))

                let isHigh = s >= spec.highFromIndex
                for p in range {
                    let r = SettingEstimator.estimate(
                        machine: spec, games: realGames,
                        counts: ["BIG": bigAt(p, i), "REG": regAt(p, i)])
                    if let best = r.posteriors.indices.max(by: { r.posteriors[$0] < r.posteriors[$1] }),
                       best == s { exactHits += 1 }
                    if (r.highProb > 0.5) == isHigh { hlHits += 1 }
                }
            }
            let total = Double(pathCount)
            return CheckpointStat(games: realGames, rows: rows,
                                  exactAccuracy: Double(exactHits) / total,
                                  highLowAccuracy: Double(hlHits) / total)
        }
    }
}
