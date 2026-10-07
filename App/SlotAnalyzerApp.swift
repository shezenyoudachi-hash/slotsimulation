import SwiftUI

@main
struct SlotAnalyzerApp: App {
    @State private var store = BankStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                EstimateView()
                    .tabItem { Label("設定推測", systemImage: "chart.bar.xaxis") }
                FluctuationView()
                    .tabItem { Label("揺れ分析", systemImage: "waveform.path.ecg") }
                MatchView()
                    .tabItem { Label("類似グラフ", systemImage: "chart.line.uptrend.xyaxis") }
            }
            .environment(store)
        }
    }
}
