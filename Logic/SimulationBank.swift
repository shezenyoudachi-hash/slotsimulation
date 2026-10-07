import Foundation

/// 高速な乱数生成器（シード指定で再現可能）
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) * 0x1.0p-53 }
}

struct BankConfig: Sendable, Hashable {
    /// 設定ごとのシミュレーション本数
    var pathsPerSetting: Int = 1000
    /// 1本あたりの最大ゲーム数
    var maxGames: Int = 8000
    /// グラフを記録する間隔（G）。ゲーム数が少ないときは細かく記録して、序盤の揺れも滑らかに描けるようにする
    var step: Int {
        switch maxGames {
        case ...2000: return 5
        case ...4000: return 10
        default: return 20
        }
    }
    var seed: UInt64 = 20251001
}

/// 全設定ぶんのスランプグラフをまとめて持つ「シミュレーション・バンク」。
/// 揺れ分析と類似グラフ同定の両方がこれを使う。
///
/// 出玉モデル（Aタイプ近似）:
///   1G ごとに BIG / REG を抽選し、当選時に獲得枚数を加算。
///   ボーナス以外の払い出し（小役・リプレイ）は、機械割と期待値が一致するよう
///   1G あたりの平均値として毎G加算する。
final class SimulationBank: Sendable {
    let spec: MachineSpec
    let config: BankConfig
    /// 1本あたりの記録点数（0G を含む）
    let pointCount: Int
    /// [path * pointCount + i] = i 番目の記録点での差枚
    let diff: [Float]
    let big: [UInt16]
    let reg: [UInt16]

    private init(spec: MachineSpec, config: BankConfig, pointCount: Int,
                 diff: [Float], big: [UInt16], reg: [UInt16]) {
        self.spec = spec
        self.config = config
        self.pointCount = pointCount
        self.diff = diff
        self.big = big
        self.reg = reg
    }

    var pathCount: Int { spec.settingCount * config.pathsPerSetting }
    var maxGames: Int { (pointCount - 1) * config.step }

    func setting(ofPath p: Int) -> Int { p / config.pathsPerSetting }
    func paths(ofSetting s: Int) -> Range<Int> {
        (s * config.pathsPerSetting)..<((s + 1) * config.pathsPerSetting)
    }
    func index(forGames g: Int) -> Int {
        min(max(Int((Double(g) / Double(config.step)).rounded()), 0), pointCount - 1)
    }
    func games(atIndex i: Int) -> Int { i * config.step }

    @inline(__always) func diffAt(_ p: Int, _ i: Int) -> Double { Double(diff[p * pointCount + i]) }
    @inline(__always) func bigAt(_ p: Int, _ i: Int) -> Int { Int(big[p * pointCount + i]) }
    @inline(__always) func regAt(_ p: Int, _ i: Int) -> Int { Int(reg[p * pointCount + i]) }

    /// バンクを生成する。キャンセルされたら nil。
    static func generate(spec: MachineSpec, config: BankConfig,
                         progress: @Sendable (Double) -> Void) -> SimulationBank? {
        let points = config.maxGames / config.step + 1
        let settings = spec.settingCount
        let total = settings * config.pathsPerSetting
        var diff = [Float](repeating: 0, count: total * points)
        var big = [UInt16](repeating: 0, count: total * points)
        var reg = [UInt16](repeating: 0, count: total * points)
        var rng = SplitMix64(seed: config.seed)
        let reportEvery = max(total / 100, 1)

        for s in 0..<settings {
            let pB = 1.0 / spec.bigDenoms[s]
            let pR = 1.0 / spec.regDenoms[s]
            let baseOut = spec.bet * spec.payoutRates[s] / 100 - spec.bigPayout * pB - spec.regPayout * pR
            let perGame = baseOut - spec.bet

            for j in 0..<config.pathsPerSetting {
                let p = s * config.pathsPerSetting + j
                if p % reportEvery == 0 {
                    if Task.isCancelled { return nil }
                    progress(Double(p) / Double(total))
                }
                var d = 0.0
                var b = 0
                var r = 0
                var k = p * points + 1
                for g in 1...config.maxGames {
                    d += perGame
                    let u = rng.uniform()
                    if u < pB { d += spec.bigPayout; b += 1 }
                    else if u < pB + pR { d += spec.regPayout; r += 1 }
                    if g % config.step == 0 {
                        diff[k] = Float(d)
                        big[k] = UInt16(min(b, Int(UInt16.max)))
                        reg[k] = UInt16(min(r, Int(UInt16.max)))
                        k += 1
                    }
                }
            }
        }
        progress(1)
        return SimulationBank(spec: spec, config: config, pointCount: points,
                              diff: diff, big: big, reg: reg)
    }
}

// MARK: - 共通の統計ヘルパー

enum Stats {
    /// ソート済み配列の分位点（線形補間）
    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        let pos = q * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }

    /// 0...upper を最大 maxPoints 個程度に間引いたインデックス列
    static func thinned(_ range: ClosedRange<Int>, maxPoints: Int) -> [Int] {
        let len = range.upperBound - range.lowerBound
        let stride = max(len / max(maxPoints, 1), 1)
        var r = Array(Swift.stride(from: range.lowerBound, through: range.upperBound, by: stride))
        if r.last != range.upperBound { r.append(range.upperBound) }
        return r
    }
}
