import Foundation

/// 実際のスランプグラフから読み取った点（G数, 差枚）
struct ObservedPoint: Identifiable, Hashable {
    var id = UUID()
    var games: Int
    var diff: Int
}

struct MatchQuery {
    /// 現在のG数と差枚（必須）
    var currentGames: Int
    var currentDiff: Int
    /// 途中経過（グラフから読み取った点。任意）
    var pastPoints: [ObservedPoint] = []
    /// ボーナス回数（分かれば。nil なら差枚の形だけで比較）
    var big: Int? = nil
    var reg: Int? = nil
    /// どこまで先を予測するか（G数）
    var horizonGames: Int
    /// 似ているとみなすシミュレーションの本数
    var neighbors: Int = 300
}

struct FanPoint: Identifiable {
    var id: Int { games }
    var games: Int
    var p5: Double
    var p25: Double
    var p50: Double
    var p75: Double
    var p95: Double
    /// 類似グラフの設定構成と機械割から出した理論上の期待値
    var theory: Double
}

struct PathPoint: Identifiable {
    var id: Int
    var path: Int
    var games: Int
    var diff: Double
}

struct MatchResult {
    var labels: [String]
    var currentGames: Int
    var currentDiff: Double
    var horizonGames: Int
    /// 類似グラフが各設定から何割来ているか（＝グラフ形状から見た設定の確率）
    var settingShares: [Double]
    var highShare: Double
    /// ボーナス回数からのベイズ推定（比較用）
    var bayes: EstimateResult?
    /// 現在地点からの今後の差枚の分布（現在の差枚を起点に揃えたもの）
    var fan: [FanPoint]
    /// 最も似ていたグラフ（表示用）
    var closestPaths: [PathPoint]
    var observed: [ObservedPoint]
    /// 予測先までの増減の中央値・平均、増える確率
    var gainMedian: Double
    var gainMean: Double
    var gainUpRate: Double
    var theoryGain: Double
    var usedNeighbors: Int
}

/// 類似グラフ同定。
/// 全設定のシミュレーションから、入力したグラフに近いものを k 本選び、
/// ①それらがどの設定から来たか ②その後どう動いたか を集計する。
extension SimulationBank {
    func match(_ q: MatchQuery, closestToShow: Int = 15) -> MatchResult? {
        guard q.currentGames > 0 else { return nil }
        let curIdx = index(forGames: q.currentGames)
        let horizonIdx = max(index(forGames: q.horizonGames), curIdx)
        let k = min(max(q.neighbors, 10), pathCount)

        // 比較に使う点（途中経過 + 現在地点）
        var points = q.pastPoints.filter { $0.games > 0 && $0.games < q.currentGames }
        points.append(ObservedPoint(games: q.currentGames, diff: q.currentDiff))
        points.sort { $0.games < $1.games }
        let idxs = points.map { index(forGames: $0.games) }

        // 各点での差枚のばらつき（全設定込み）で正規化する
        let scales: [Double] = idxs.map { i in
            var s = 0.0, s2 = 0.0
            for p in 0..<pathCount { let v = diffAt(p, i); s += v; s2 += v * v }
            let n = Double(pathCount)
            return max(sqrt(max(s2 / n - (s / n) * (s / n), 0)), 1)
        }
        // ボーナス回数の比較は Poisson 近似（分散 ≈ 平均）
        func meanCount(_ get: (Int, Int) -> Int) -> Double {
            var s = 0
            for p in 0..<pathCount { s += get(p, curIdx) }
            return max(Double(s) / Double(pathCount), 1)
        }
        let bigVar = q.big != nil ? meanCount(bigAt) : 1
        let regVar = q.reg != nil ? meanCount(regAt) : 1

        // 途中経過は点の数によらず「2点ぶん」の重みにする。
        // グラフをなぞると点が20個ほどになり、そのままだと形の比較だけで決まってしまうため。
        let lastJ = idxs.count - 1
        let pastWeight = lastJ > 0 ? 2.0 / Double(lastJ) : 0

        var dist = [(Double, Int)]()
        dist.reserveCapacity(pathCount)
        for p in 0..<pathCount {
            var d = 0.0
            for (j, i) in idxs.enumerated() {
                let z = (diffAt(p, i) - Double(points[j].diff)) / scales[j]
                d += z * z * (j == lastJ ? 1 : pastWeight)
            }
            if let b = q.big { let x = Double(bigAt(p, curIdx) - b); d += x * x / bigVar }
            if let r = q.reg { let x = Double(regAt(p, curIdx) - r); d += x * x / regVar }
            dist.append((d, p))
        }
        dist.sort { $0.0 < $1.0 }
        let chosen = dist.prefix(k).map { $0.1 }

        // 設定の構成比
        var shares = Array(repeating: 0.0, count: spec.settingCount)
        for p in chosen { shares[setting(ofPath: p)] += 1 }
        shares = shares.map { $0 / Double(chosen.count) }
        let highShare = shares[spec.highFromIndex...].reduce(0, +)
        let mixPerGame = shares.enumerated().map { $0.element * spec.expectedDiffPerGame($0.offset) }.reduce(0, +)

        // 今後の動き：各類似グラフの「現在地点からの増減」を現在の差枚に足す
        let cur = Double(q.currentDiff)
        let curG = games(atIndex: curIdx)
        var fan: [FanPoint] = []
        for i in Stats.thinned(curIdx...horizonIdx, maxPoints: 50) {
            let vals = chosen.map { cur + diffAt($0, i) - diffAt($0, curIdx) }.sorted()
            let g = games(atIndex: i)
            fan.append(FanPoint(games: g,
                                p5: Stats.quantile(vals, 0.05),
                                p25: Stats.quantile(vals, 0.25),
                                p50: Stats.quantile(vals, 0.5),
                                p75: Stats.quantile(vals, 0.75),
                                p95: Stats.quantile(vals, 0.95),
                                theory: cur + mixPerGame * Double(g - curG)))
        }
        let gains = chosen.map { diffAt($0, horizonIdx) - diffAt($0, curIdx) }.sorted()

        var closest: [PathPoint] = []
        var pid = 0
        for p in chosen.prefix(closestToShow) {
            for i in Stats.thinned(0...horizonIdx, maxPoints: 60) {
                closest.append(PathPoint(id: pid, path: p, games: games(atIndex: i), diff: diffAt(p, i)))
                pid += 1
            }
        }

        var bayes: EstimateResult? = nil
        if q.big != nil || q.reg != nil {
            var counts: [String: Int] = [:]
            if let b = q.big { counts["BIG"] = b }
            if let r = q.reg { counts["REG"] = r }
            bayes = SettingEstimator.estimate(machine: spec, games: q.currentGames, counts: counts)
        }

        return MatchResult(labels: spec.labels,
                           currentGames: curG, currentDiff: cur,
                           horizonGames: games(atIndex: horizonIdx),
                           settingShares: shares, highShare: highShare, bayes: bayes,
                           fan: fan, closestPaths: closest, observed: points,
                           gainMedian: Stats.quantile(gains, 0.5),
                           gainMean: gains.reduce(0, +) / Double(gains.count),
                           gainUpRate: Double(gains.filter { $0 > 0 }.count) / Double(gains.count),
                           theoryGain: mixPerGame * Double(games(atIndex: horizonIdx) - curG),
                           usedNeighbors: chosen.count)
    }
}
