import SwiftUI

@main
struct SlotAnalyzerApp: App {
    @State private var store = BankStore()
    @State private var validationStore = ValidationStore()
    @State private var playStore = PlayStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                RecordView()
                    .tabItem { Label("記録", systemImage: "square.and.pencil") }
                EstimateView()
                    .tabItem { Label("設定推測", systemImage: "chart.bar.xaxis") }
                FluctuationView()
                    .tabItem { Label("揺れ分析", systemImage: "waveform.path.ecg") }
                MatchView()
                    .tabItem { Label("類似グラフ", systemImage: "chart.line.uptrend.xyaxis") }
                ValidationView()
                    .tabItem { Label("検証", systemImage: "checkmark.seal") }
            }
            .environment(store)
            .environment(validationStore)
            .environment(playStore)
        }
    }
}
