import Foundation

struct EstimateResult {
    var labels: [String]
    /// 各設定の事後確率（合計 1）
    var posteriors: [Double]
    /// 高設定（highFromIndex 以上）の事後確率
    var highProb: Double
    /// 設定の期待値（ラベルが数字ならその値、そうでなければ 1 始まりの番号）
    var expectedSetting: Double
    /// 推測に使った役の数（0 なら事前分布のまま）
    var usedRoles: Int
}

/// ベイズ推定による設定推測。
/// 各役の出現回数を二項分布とみなし、設定ごとの尤度 × 事前分布 から事後確率を出す。
enum SettingEstimator {
    static func estimate(machine: MachineSpec,
                         games: Int,
                         counts: [String: Int],
                         prior: [Double]? = nil) -> EstimateResult {
        estimate(labels: machine.labels,
                 highFromIndex: machine.highFromIndex,
                 roles: machine.allRoles,
                 games: games, counts: counts, prior: prior)
    }

    static func estimate(labels: [String],
                         highFromIndex: Int,
                         roles: [RoleSpec],
                         games: Int,
                         counts: [String: Int],
                         prior: [Double]? = nil) -> EstimateResult {
        let n = labels.count
        guard n > 0 else {
            return EstimateResult(labels: [], posteriors: [], highProb: 0, expectedSetting: 0, usedRoles: 0)
        }
        let basePrior: [Double] = {
            if let p = prior, p.count == n, p.reduce(0, +) > 0 { return p }
            return Array(repeating: 1.0 / Double(n), count: n)
        }()

        var logPost = basePrior.map { log(max($0, 1e-300)) }
        var used = 0
        if games > 0 {
            for role in roles where role.denominators.count == n {
                guard let k = counts[role.name], k >= 0, k <= games else { continue }
                used += 1
                for i in 0..<n {
                    let d = role.denominators[i]
                    guard d > 1 else { continue }
                    let p = 1.0 / d
                    // 二項分布の対数尤度（組合せ項は設定間で共通なので省略）
                    logPost[i] += Double(k) * log(p) + Double(games - k) * log1p(-p)
                }
            }
        }

        // log-sum-exp で正規化（大きなゲーム数でもアンダーフローしない）
        let m = logPost.max() ?? 0
        let exps = logPost.map { exp($0 - m) }
        let sum = exps.reduce(0, +)
        let post = exps.map { $0 / sum }

        let from = min(max(highFromIndex, 0), n)
        let high = post[from...].reduce(0, +)
        let values = labels.enumerated().map { Double($0.element) ?? Double($0.offset + 1) }
        let expected = zip(post, values).map(*).reduce(0, +)

        return EstimateResult(labels: labels, posteriors: post, highProb: high,
                              expectedSetting: expected, usedRoles: used)
    }
}
