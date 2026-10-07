import Foundation

/// BIG/REG 以外の役（小役など）の確率。設定ごとの分母（1/x の x）を持つ。
struct RoleSpec: Codable, Hashable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    var denominators: [Double]
}

/// 機種スペック（メーカー公表値）。Aタイプ（BIG/REG で出玉を作る機種）を想定。
struct MachineSpec: Codable, Hashable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    /// 設定の表記
    var labels: [String]
    /// この index 以上を「高設定」とみなす（6段階なら 3 = 設定4以上）
    var highFromIndex: Int
    /// ボーナス1回あたりの獲得枚数（約）
    var bigPayout: Double
    var regPayout: Double
    /// 設定ごとの分母（1/x の x）
    var bigDenoms: [Double]
    var regDenoms: [Double]
    /// 機械割（%）
    var payoutRates: [Double]
    /// 追加の判別要素（公表値があるものだけ入れる）
    var extraRoles: [RoleSpec] = []
    /// 1G あたりの投入枚数
    var bet: Double = 3

    var settingCount: Int { labels.count }

    var allRoles: [RoleSpec] {
        [RoleSpec(name: "BIG", denominators: bigDenoms),
         RoleSpec(name: "REG", denominators: regDenoms)] + extraRoles
    }

    /// 設定 i の 1G あたり期待差枚
    func expectedDiffPerGame(_ i: Int) -> Double {
        bet * (payoutRates[i] / 100 - 1)
    }
}

enum MachineCatalog {
    /// ネオアイムジャグラーEX（北電子, 2025年9月導入）
    /// BIG/REG 確率・機械割・獲得枚数は公表スペック。ぶどう等の小役は公表値ではないため未収録。
    static let neoImJugglerEX = MachineSpec(
        name: "ネオアイムジャグラーEX",
        labels: ["1", "2", "3", "4", "5", "6"],
        highFromIndex: 3,
        bigPayout: 252,
        regPayout: 96,
        bigDenoms: [273.1, 269.7, 269.7, 259.0, 259.0, 255.0],
        regDenoms: [439.8, 399.6, 331.0, 315.1, 255.0, 255.0],
        payoutRates: [97.0, 98.0, 99.5, 101.1, 103.3, 105.5])

    /// 機種を増やすときはここに追加する
    static let all: [MachineSpec] = [neoImJugglerEX]
}
