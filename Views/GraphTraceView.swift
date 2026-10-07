import SwiftUI
import PhotosUI

/// データカウンターのグラフの写真を読み込み、指でなぞって差枚の推移を取り込む画面
struct GraphTraceView: View {
    @Environment(\.dismiss) private var dismiss

    /// 現在のゲーム数（なぞった線の右端がこのG数になる）
    let currentGames: Int
    /// 取り込んだ途中経過の点と、現在の差枚を返す
    var onApply: (_ points: [ObservedPoint], _ currentDiff: Int) -> Void

    private enum Mode: String, CaseIterable, Identifiable {
        case scale = "① 目盛りを合わせる"
        case trace = "② なぞる"
        var id: String { rawValue }
    }

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var mode: Mode = .scale

    /// 0枚の線と、目盛りの線の y 座標（キャンバス内）
    @State private var zeroY: CGFloat?
    @State private var refY: CGFloat?
    @State private var refValue = 2000
    /// 目盛り合わせで今動かしている線（true = 0枚の線）
    @State private var draggingZero: Bool?

    @State private var stroke: [CGPoint] = []
    @State private var isDrawing = false

    /// 何点に分けて取り込むか
    private let sampleCount = 20

    var body: some View {
        NavigationStack {
            // ScrollView に入れると、なぞる操作がスクロールに取られるので使わない
            VStack(alignment: .leading, spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(image == nil ? "グラフの写真を選ぶ" : "写真を選び直す",
                          systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)

                Picker("手順", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(instruction)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                canvas
                    .frame(maxHeight: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))

                if mode == .scale {
                    HStack {
                        Text("オレンジの線の値")
                        Spacer()
                        TextField("枚数", value: $refValue, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                        Text("枚")
                    }
                } else {
                    Button("なぞり直す", role: .destructive) { stroke = [] }
                        .disabled(stroke.isEmpty)
                }

                resultSummary
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("グラフをなぞって入力")
            .navigationBarTitleDisplayMode(.inline)
            // 下向きになぞったときにシートが閉じないようにする
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("反映") {
                        if let r = converted() {
                            onApply(r.points, r.current)
                            dismiss()
                        }
                    }
                    .disabled(converted() == nil)
                }
            }
            .task(id: pickerItem) {
                guard let item = pickerItem,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let ui = UIImage(data: data) else { return }
                image = ui
                stroke = []
                mode = .scale
            }
        }
    }

    private var instruction: String {
        switch mode {
        case .scale:
            return "青い線をグラフの「0枚」の線に、オレンジの線を目盛りの線（例：+2000）に、指で動かして合わせてください。オレンジの線の値も下で入力します。"
        case .trace:
            return "グラフの左端（0G）から現在の位置まで、線を指でなぞってください。右端が現在のゲーム数（\(currentGames)G）になります。"
        }
    }

    // MARK: - キャンバス

    private var canvas: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                background(size: geo.size)

                if let z = zeroY {
                    guideLine(y: z, width: geo.size.width, color: .blue, label: "0枚")
                }
                if let r = refY {
                    guideLine(y: r, width: geo.size.width, color: .orange,
                              label: "\(refValue > 0 ? "+" : "")\(refValue)枚")
                }

                Path { path in
                    guard let first = stroke.first else { return }
                    path.move(to: first)
                    for p in stroke.dropFirst() { path.addLine(to: p) }
                }
                .stroke(.red, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                if let r = converted() {
                    ForEach(r.canvasPoints.indices, id: \.self) { i in
                        Circle()
                            .fill(.red)
                            .frame(width: 7, height: 7)
                            .position(r.canvasPoints[i])
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .highPriorityGesture(dragGesture(height: geo.size.height))
            .onAppear {
                if zeroY == nil { zeroY = geo.size.height * 0.55 }
                if refY == nil { refY = geo.size.height * 0.15 }
            }
        }
    }

    @ViewBuilder
    private func background(size: CGSize) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        } else {
            // 写真が無いときは方眼紙の上に描けるようにする
            Path { path in
                let step: CGFloat = 30
                var x: CGFloat = 0
                while x <= size.width { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y <= size.height { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)); y += step }
            }
            .stroke(.secondary.opacity(0.15), lineWidth: 0.5)
            .background(Color(.secondarySystemBackground))
        }
    }

    private func guideLine(y: CGFloat, width: CGFloat, color: Color, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: .init(x: 0, y: y))
                p.addLine(to: .init(x: width, y: y))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: mode == .scale ? [] : [6, 4]))
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 4)
                .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
                .position(x: width - 40, y: max(y - 12, 10))
        }
        .allowsHitTesting(false)
    }

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let y = min(max(value.location.y, 0), height)
                switch mode {
                case .scale:
                    // 触り始めた位置に近いほうの線を動かす
                    if draggingZero == nil, let z = zeroY, let r = refY {
                        draggingZero = abs(value.startLocation.y - z) <= abs(value.startLocation.y - r)
                    }
                    if draggingZero == true { zeroY = y } else { refY = y }
                case .trace:
                    if !isDrawing { stroke = []; isDrawing = true }
                    stroke.append(CGPoint(x: value.location.x, y: y))
                }
            }
            .onEnded { _ in
                draggingZero = nil
                isDrawing = false
            }
    }

    // MARK: - 変換

    private struct Converted {
        var points: [ObservedPoint]
        var current: Int
        var canvasPoints: [CGPoint]
    }

    /// なぞった線を (G数, 差枚) に変換する。条件が揃っていなければ nil
    private func converted() -> Converted? {
        guard currentGames > 0, let z = zeroY, let r = refY, abs(z - r) > 10, refValue != 0 else { return nil }

        // 左から右へ進む点だけを使う（戻った部分は無視）
        var pts: [CGPoint] = []
        for p in stroke where p.x > (pts.last?.x ?? -.infinity) { pts.append(p) }
        guard let first = pts.first, let last = pts.last, last.x - first.x > 20 else { return nil }

        func value(atY y: CGFloat) -> Int {
            Int(((z - y) / (z - r) * CGFloat(refValue)).rounded())
        }
        func y(atX x: CGFloat) -> CGFloat {
            guard let i = pts.firstIndex(where: { $0.x >= x }) else { return last.y }
            if i == 0 { return pts[0].y }
            let a = pts[i - 1], b = pts[i]
            let t = (x - a.x) / max(b.x - a.x, 0.001)
            return a.y + (b.y - a.y) * t
        }

        var out: [ObservedPoint] = []
        var canvasPts: [CGPoint] = []
        for k in 1..<sampleCount {
            let t = CGFloat(k) / CGFloat(sampleCount)
            let x = first.x + (last.x - first.x) * t
            let yy = y(atX: x)
            out.append(ObservedPoint(games: Int((Double(currentGames) * Double(t)).rounded()),
                                     diff: value(atY: yy)))
            canvasPts.append(CGPoint(x: x, y: yy))
        }
        canvasPts.append(last)
        return Converted(points: out, current: value(atY: last.y), canvasPoints: canvasPts)
    }

    @ViewBuilder
    private var resultSummary: some View {
        if let r = converted() {
            let peak = (r.points.map(\.diff) + [r.current]).max() ?? 0
            let bottom = (r.points.map(\.diff) + [r.current]).min() ?? 0
            VStack(alignment: .leading, spacing: 4) {
                Text("読み取り結果").font(.subheadline.bold())
                Text("現在 \(currentGames)G：\(Fmt.signed(Double(r.current)))枚")
                Text("最高 \(Fmt.signed(Double(peak)))枚 ／ 最低 \(Fmt.signed(Double(bottom)))枚")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote.monospacedDigit())
        } else if mode == .trace {
            Text("まだ線がありません")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
