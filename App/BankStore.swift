import SwiftUI

/// 選択中の機種と、生成済みのシミュレーション・バンクを全タブで共有する
@Observable
@MainActor
final class BankStore {
    var spec: MachineSpec = MachineCatalog.neoImJugglerEX
    var config = BankConfig()
    private(set) var bank: SimulationBank?
    private(set) var progress: Double = 0
    private(set) var isRunning = false
    /// 揺れ分析の結果（重いのでバンク生成時に一緒に計算しておく）
    private(set) var bands: [BandPoint] = []
    private(set) var checkpoints: [CheckpointStat] = []

    private var task: Task<Void, Never>?

    /// 今のバンクが現在の機種・設定で作られたものか
    var isBankCurrent: Bool {
        bank?.spec == spec && bank?.config == config
    }

    func generate() {
        task?.cancel()
        isRunning = true
        progress = 0
        let spec = spec
        let config = config
        let report: @Sendable (Double) -> Void = { [weak self] p in
            Task { @MainActor in self?.progress = p * 0.9 }
        }
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                () -> (SimulationBank, [BandPoint], [CheckpointStat])? in
                guard let bank = SimulationBank.generate(spec: spec, config: config, progress: report)
                else { return nil }
                if Task.isCancelled { return nil }
                return (bank, bank.bands(), bank.checkpointStats())
            }
            // このタスクがキャンセルされたら裏の計算も止める
            let output = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, !Task.isCancelled else { return }
            if let output {
                self.bank = output.0
                self.bands = output.1
                self.checkpoints = output.2
            }
            self.progress = 1
            self.isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
        isRunning = false
    }
}

/// バンク生成の設定とボタン（揺れ分析・類似グラフの両タブで使う）
struct BankControlSection: View {
    @Environment(BankStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section {
            LabeledContent("機種", value: store.spec.name)
            Picker("設定ごとの本数", selection: $store.config.pathsPerSetting) {
                ForEach([500, 1000, 2000, 5000], id: \.self) { Text("\($0)本").tag($0) }
            }
            Picker("最大ゲーム数", selection: $store.config.maxGames) {
                ForEach([2000, 4000, 8000, 10000], id: \.self) { Text("\($0)G").tag($0) }
            }
            if store.isRunning {
                HStack {
                    ProgressView(value: store.progress)
                    Button("中止", role: .cancel) { store.cancel() }
                }
            } else {
                Button(store.bank == nil ? "シミュレーションを生成" : "作り直す") { store.generate() }
            }
        } header: {
            Text("シミュレーション")
        } footer: {
            if let bank = store.bank {
                Text("生成済み：全\(bank.pathCount)本 × \(bank.maxGames)G"
                     + (store.isBankCurrent ? "" : "（条件が変わっています。作り直してください）"))
            } else {
                Text("設定1〜6のスランプグラフを大量に作ります。本数を増やすほど精度は上がりますが時間がかかります。")
            }
        }
    }
}

// MARK: - 共通の小物

struct IntField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            TextField(title, value: $value, format: .number)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
        }
    }
}

enum Fmt {
    static func signed(_ v: Double) -> String {
        let n = Int(v.rounded())
        return (n > 0 ? "+" : "") + n.formatted()
    }
    static func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
    static func denom(_ v: Double) -> String { v.isFinite ? String(format: "1/%.0f", v) : "—" }
}
