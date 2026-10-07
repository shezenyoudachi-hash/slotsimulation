import Foundation
import Observation

/// 予測の検証用に記録する1台1日分のデータ。
/// 「途中」は判断する時点（例：2000G）、「最終」は閉店時などの最終データ。
struct ValidationRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var unit: Int?

    var checkGames = 0
    var checkBig = 0
    var checkReg = 0
    var checkDiff: Int?

    var finalGames: Int?
    var finalBig: Int?
    var finalReg: Int?
    var finalDiff: Int?
    var memo = ""

    /// 最終データまで揃っていて、途中より後に進んでいるか
    var isComplete: Bool {
        guard let g = finalGames, let b = finalBig, let r = finalReg else { return false }
        return g > checkGames && b >= checkBig && r >= checkReg && checkGames >= 0
    }

    var hasDiffs: Bool { checkDiff != nil && finalDiff != nil }
}

/// 記録を端末内（アプリの書類フォルダ）に JSON で保存する
@Observable
@MainActor
final class ValidationStore {
    private(set) var records: [ValidationRecord] = []

    private let fileURL: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("validation-records.json")

    init() { load() }

    func upsert(_ r: ValidationRecord) {
        if let i = records.firstIndex(where: { $0.id == r.id }) { records[i] = r } else { records.append(r) }
        sortAndSave()
    }

    func delete(ids: Set<UUID>) {
        records.removeAll { ids.contains($0.id) }
        save()
    }

    func append(_ new: [ValidationRecord]) {
        records.append(contentsOf: new)
        sortAndSave()
    }

    private func sortAndSave() {
        records.sort { ($0.date, $0.unit ?? 0) > ($1.date, $1.unit ?? 0) }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        records = (try? dec.decode([ValidationRecord].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - CSV

/// CSV の列順（1行目が見出しなら読み飛ばす）
/// 日付,台番,途中G数,途中BIG,途中REG,途中差枚,最終G数,最終BIG,最終REG,最終差枚
enum ValidationCSV {
    static let header = "日付,台番,途中G数,途中BIG,途中REG,途中差枚,最終G数,最終BIG,最終REG,最終差枚"

    private static let dateFormats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy/M/d", "yyyy-M-d", "M/d/yyyy"]

    private static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        for fmt in dateFormats {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static func int(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "枚", with: "")
            .replacingOccurrences(of: "\"", with: "")
        return t.isEmpty ? nil : Int(t)
    }

    /// 取り込めた記録と、読めなかった行数を返す
    static func parse(_ text: String) -> (records: [ValidationRecord], skipped: Int) {
        var out: [ValidationRecord] = []
        var skipped = 0
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)

        for (n, raw) in lines.enumerated() {
            let cols = raw.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "") }
            func col(_ i: Int) -> String { i < cols.count ? cols[i] : "" }

            guard let date = parseDate(col(0)),
                  let cg = int(col(2)), let cb = int(col(3)), let cr = int(col(4)) else {
                if n > 0 { skipped += 1 }   // 1行目の見出しは数えない
                continue
            }
            var r = ValidationRecord()
            r.date = date
            r.unit = int(col(1))
            r.checkGames = cg
            r.checkBig = cb
            r.checkReg = cr
            r.checkDiff = int(col(5))
            r.finalGames = int(col(6))
            r.finalBig = int(col(7))
            r.finalReg = int(col(8))
            r.finalDiff = int(col(9))
            out.append(r)
        }
        return (out, skipped)
    }

    static func make(_ records: [ValidationRecord]) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        func s(_ v: Int?) -> String { v.map(String.init) ?? "" }
        let rows = records.map { r in
            [f.string(from: r.date), s(r.unit), String(r.checkGames), String(r.checkBig), String(r.checkReg),
             s(r.checkDiff), s(r.finalGames), s(r.finalBig), s(r.finalReg), s(r.finalDiff)].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// Excel で保存した CSV は Shift_JIS のことがあるので両方試す
    static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS)
    }
}
