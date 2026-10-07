import Foundation

/// 店の設定配分（事前分布）
enum PriorPreset: String, CaseIterable, Identifiable {
    case uniform = "均等"
    case lowHeavy = "高設定少なめ（例）"
    case custom = "カスタム"
    var id: String { rawValue }

    /// 設定1〜6の割合（%）
    var percents: [Double]? {
        switch self {
        case .uniform: return Array(repeating: 100.0 / 6, count: 6)
        case .lowHeavy: return [40, 25, 15, 10, 6, 4]
        case .custom: return nil
        }
    }
}

/// 値と確率の組で表した離散分布
struct DiscreteDist {
    private(set) var values: [Double] = []
    private(set) var probs: [Double] = []

    /// binWidth を指定すると、その幅ごとに値をまとめる（差枚のように値の種類が多いときの計算を軽くする）
    init(pairs: [(Double, Double)], binWidth: Double? = nil) {
        var merged: [Double: Double] = [:]
        for (x, p) in pairs where p > 0 {
            let key = binWidth.map { ($0 * (x / $0).rounded()) } ?? x
            merged[key, default: 0] += p
        }
        for (x, p) in merged.sorted(by: { $0.key < $1.key }) {
            values.append(x)
            probs.append(p)
        }
        let total = probs.reduce(0, +)
        if total > 0 { probs = probs.map { $0 / total } }
    }

    var mean: Double { zip(values, probs).map(*).reduce(0, +) }

    func quantile(_ q: Double) -> Double {
        var c = 0.0
        for (x, p) in zip(values, probs) {
            c += p
            if c >= q - 1e-12 { return x }
        }
        return values.last ?? 0
    }

    /// 実際の値が予測分布のどの位置に来たか（0〜1）。
    /// 予測が正しければ、多数の台でこの値は 0〜1 に均等に散らばる。
    /// 回数のような飛び飛びの値でも偏らないよう、同じ値の確率は半分ずつ数える。
    func midPIT(_ x: Double, tolerance: Double = 0.5) -> Double {
        var below = 0.0, equal = 0.0
        for (v, p) in zip(values, probs) {
            if v < x - tolerance { below += p } else if v <= x + tolerance { equal += p }
        }
        return below + equal / 2
    }
}

enum Binomial {
    /// 二項分布の確率（0回〜十分大きい回数まで）
    static func pmf(n: Int, p: Double) -> [Double] {
        guard n > 0, p > 0 else { return [1] }
        let mean = Double(n) * p
        let sd = (Double(n) * p * (1 - p)).squareRoot()
        let kmax = min(n, Int(mean + 12 * sd + 15))
        // 長い式を1行で書くと型の推論が終わらずビルドエラーになるので、項ごとに分けて型を明示する
        let nn: Double = Double(n)
        let lnN: Double = lgamma(nn + 1)
        let logP: Double = log(p)
        let logQ: Double = log1p(-p)
        var result: [Double] = []
        result.reserveCapacity(kmax + 1)
        for i in 0...kmax {
            let k: Double = Double(i)
            let logChoose: Double = lnN - lgamma(k + 1) - lgamma(nn - k + 1)
            let logProb: Double = logChoose + k * logP + (nn - k) * logQ
            result.append(exp(logProb))
        }
        return result
    }
}

/// 1項目（BIG・REG・差枚の増減）の予測と実績
struct OutcomeCheck {
    var predictedMean: Double
    var actual: Double
    var pit: Double
    var lo90: Double
    var hi90: Double
}

struct RecordCheck: Identifiable {
    var id: UUID
    var record: ValidationRecord
    var remainingGames: Int
    /// 途中データから見た「設定4以上」の確率
    var highProb: Double
    /// 途中データから見た機械割の期待値（%）
    var expectedRate: Double
    var big: OutcomeCheck
    var reg: OutcomeCheck
    var diff: OutcomeCheck?
}

struct CoverageStat {
    var n: Int
    /// 予測の50%範囲・90%範囲に実際の値が入った割合（理想はそれぞれ50%・90%）
    var cover50: Double
    var cover90: Double
    var predictedTotal: Double
    var actualTotal: Double
    /// PIT を10区間に分けた件数（理想は平ら）
    var histogram: [Int]

    init?(_ items: [OutcomeCheck]) {
        guard !items.isEmpty else { return nil }
        n = items.count
        cover50 = Double(items.filter { abs($0.pit - 0.5) <= 0.25 }.count) / Double(n)
        cover90 = Double(items.filter { $0.pit >= 0.05 && $0.pit <= 0.95 }.count) / Double(n)
        predictedTotal = items.map(\.predictedMean).reduce(0, +)
        actualTotal = items.map(\.actual).reduce(0, +)
        var h = Array(repeating: 0, count: 10)
        for i in items { h[min(Int(i.pit * 10), 9)] += 1 }
        histogram = h
    }
}

struct ConfidenceBucket: Identifiable {
    var id: String { label }
    var label: String
    var count: Int
    var remainingGames: Int
    var predictedReg: Double
    var actualReg: Int
    /// 差枚が揃っている台だけで計算した機械割（%）
    var predictedRate: Double?
    var actualRate: Double?

    var predictedRegDenom: Double { predictedReg > 0 ? Double(remainingGames) / predictedReg : .infinity }
    var actualRegDenom: Double { actualReg > 0 ? Double(remainingGames) / Double(actualReg) : .infinity }
}

struct ValidationSummary {
    var checks: [RecordCheck]
    var big: CoverageStat?
    var reg: CoverageStat?
    var diff: CoverageStat?
    var buckets: [ConfidenceBucket]
}

/// 途中データから「その後」を予測し、最終データと比べる
enum PredictionCheck {
    static func evaluate(_ r: ValidationRecord, spec: MachineSpec, prior: [Double]) -> RecordCheck? {
        guard r.isComplete, let fg = r.finalGames, let fb = r.finalBig, let fr = r.finalReg else { return nil }
        let n = fg - r.checkGames
        let est = SettingEstimator.estimate(machine: spec, games: r.checkGames,
                                            counts: ["BIG": r.checkBig, "REG": r.checkReg], prior: prior)
        let post = est.posteriors
        let withDiff = r.hasDiffs

        var bigPairs: [(Double, Double)] = []
        var regPairs: [(Double, Double)] = []
        var diffPairs: [(Double, Double)] = []

        for s in post.indices where post[s] > 1e-9 {
            let pB = 1 / spec.bigDenoms[s]
            let pR = 1 / spec.regDenoms[s]
            let bm = Binomial.pmf(n: n, p: pB)
            let rm = Binomial.pmf(n: n, p: pR)
            for (k, q) in bm.enumerated() { bigPairs.append((Double(k), post[s] * q)) }
            for (k, q) in rm.enumerated() { regPairs.append((Double(k), post[s] * q)) }

            if withDiff {
                // シミュレーションと同じ出玉モデル：毎Gの平均払い出し + ボーナス獲得
                let perGame = spec.bet * spec.payoutRates[s] / 100 - spec.bigPayout * pB - spec.regPayout * pR - spec.bet
                let base = Double(n) * perGame
                for (b, qb) in bm.enumerated() where qb > 1e-10 {
                    for (k, qr) in rm.enumerated() where qb * qr > 1e-12 {
                        let bonusOut: Double = spec.bigPayout * Double(b) + spec.regPayout * Double(k)
                        let prob: Double = post[s] * qb * qr
                        diffPairs.append((base + bonusOut, prob))
                    }
                }
            }
        }

        func check(_ pairs: [(Double, Double)], actual: Double, bin: Double? = nil) -> OutcomeCheck {
            let d = DiscreteDist(pairs: pairs, binWidth: bin)
            return OutcomeCheck(predictedMean: d.mean, actual: actual,
                                pit: d.midPIT(actual, tolerance: (bin ?? 1) / 2 - 1e-9),
                                lo90: d.quantile(0.05), hi90: d.quantile(0.95))
        }

        var diffCheck: OutcomeCheck? = nil
        if withDiff, let cd = r.checkDiff, let fd = r.finalDiff {
            diffCheck = check(diffPairs, actual: Double(fd - cd), bin: 4)
        }
        let expectedRate = zip(post, spec.payoutRates).map(*).reduce(0, +)

        return RecordCheck(id: r.id, record: r, remainingGames: n,
                           highProb: est.highProb, expectedRate: expectedRate,
                           big: check(bigPairs, actual: Double(fb - r.checkBig)),
                           reg: check(regPairs, actual: Double(fr - r.checkReg)),
                           diff: diffCheck)
    }

    static func summarize(_ records: [ValidationRecord], spec: MachineSpec, prior: [Double]) -> ValidationSummary {
        let checks = records.compactMap { evaluate($0, spec: spec, prior: prior) }

        let edges: [(String, ClosedRange<Double>)] = [
            ("0〜20%", 0...0.2), ("20〜40%", 0.2...0.4), ("40〜60%", 0.4...0.6),
            ("60〜80%", 0.6...0.8), ("80〜100%", 0.8...1.0)
        ]
        let buckets: [ConfidenceBucket] = edges.compactMap { label, range in
            let items = checks.filter {
                range.contains($0.highProb) && ($0.highProb < range.upperBound || range.upperBound == 1.0)
            }
            guard !items.isEmpty else { return nil }
            let games = items.map(\.remainingGames).reduce(0, +)
            let withDiff = items.filter { $0.diff != nil }
            let diffGames = withDiff.map(\.remainingGames).reduce(0, +)
            func rate(_ total: Double) -> Double { 100 * (1 + total / (spec.bet * Double(diffGames))) }
            return ConfidenceBucket(
                label: label, count: items.count, remainingGames: games,
                predictedReg: items.map(\.reg.predictedMean).reduce(0, +),
                actualReg: Int(items.map(\.reg.actual).reduce(0, +)),
                predictedRate: diffGames > 0 ? rate(withDiff.map { $0.diff!.predictedMean }.reduce(0, +)) : nil,
                actualRate: diffGames > 0 ? rate(withDiff.map { $0.diff!.actual }.reduce(0, +)) : nil)
        }

        return ValidationSummary(checks: checks,
                                 big: CoverageStat(checks.map(\.big)),
                                 reg: CoverageStat(checks.map(\.reg)),
                                 diff: CoverageStat(checks.compactMap(\.diff)),
                                 buckets: buckets)
    }
}
