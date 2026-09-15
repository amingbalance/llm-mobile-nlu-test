//
//  ContentView.swift
//  llm_test
//

import SwiftUI

struct QuickTestView: View {
    @State private var parser = ExpenseParser()
    @State private var input = SampleSentences.all[0]
    @State private var streaming = true
    @State private var usePrewarmed = true
    @State private var isRunning = false
    @State private var results: [ParseResult] = []

    var body: some View {
        NavigationStack {
            Form {
                availabilitySection
                inputSection
                if let latest = results.first { resultSection(latest) }
                if results.count > 1 { historySection }
            }
            .navigationTitle("LLM 記帳解析測速")
            .onAppear { if usePrewarmed { parser.prepareNextSession() } }
        }
    }

    // MARK: Sections

    private var availabilitySection: some View {
        Section("模型狀態") {
            switch parser.availability {
            case .checking:
                Label("檢查中…", systemImage: "hourglass")
            case .available:
                Label("Apple Intelligence 裝置端模型可用", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .unavailable(let reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("重新檢查") { parser.refreshAvailability() }
            }
        }
    }

    private var inputSection: some View {
        Section("輸入") {
            TextField("例如：我昨晚用北辰卡花了 180 買摩斯當晚餐", text: $input, axis: .vertical)
                .lineLimit(2...4)

            Menu("帶入測試句") {
                ForEach(SampleSentences.all, id: \.self) { s in
                    Button(s) { input = s }
                }
            }

            Toggle("串流（量 TTFT）", isOn: $streaming)
            Toggle("使用預熱 session", isOn: $usePrewarmed)
                .onChange(of: usePrewarmed) { _, on in
                    if on { parser.prepareNextSession() }
                }

            HStack {
                Button {
                    Task { await runOne(input) }
                } label: {
                    Label("解析", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRun || input.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()

                Button {
                    Task { await runBatch() }
                } label: {
                    Label("跑全部測試句", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!canRun)

                if isRunning { ProgressView().padding(.leading, 8) }
            }
        }
    }

    private func resultSection(_ r: ParseResult) -> some View {
        Section("最新結果") {
            Text(r.input).font(.subheadline).foregroundStyle(.secondary)
            if let rec = r.record {
                LabeledContent("付款方式", value: rec.paymentMethod ?? "—")
                LabeledContent("金額", value: "\(rec.amount)")
                LabeledContent("類別", value: rec.category)
                LabeledContent("日期") {
                    VStack(alignment: .trailing) {
                        Text(rec.date)
                        Text(rec.dateText.isEmpty ? "（句中沒提日期）" : "「\(rec.dateText)」\(rec.dateResolved ? "" : " 看不懂，退回今天")")
                            .font(.caption)
                            .foregroundStyle(rec.dateResolved ? Color.secondary : Color.orange)
                    }
                }
                LabeledContent("備註", value: rec.note)
            }
            if let err = r.error {
                Label(err, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
            MetricsView(m: r.metrics)
        }
    }

    private var historySection: some View {
        Section {
            ForEach(results) { r in
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.input).font(.footnote)
                    HStack {
                        if let rec = r.record {
                            Text("\(rec.paymentMethod ?? "—") / \(rec.amount) / \(rec.category) / \(rec.date) / \(rec.note)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(r.error ?? "失敗").font(.caption).foregroundStyle(.red)
                        }
                        Spacer()
                        Text(String(format: "%.2fs", r.metrics.totalSeconds))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        } header: {
            HStack {
                Text("歷史（\(results.count) 筆）")
                Spacer()
                Text(String(format: "平均 %.2fs", averageSeconds))
                Button("清除") { results.removeAll() }.font(.caption)
            }
        }
    }

    // MARK: Actions

    private var canRun: Bool { parser.availability == .available && !isRunning }

    private var averageSeconds: Double {
        guard !results.isEmpty else { return 0 }
        return results.map(\.metrics.totalSeconds).reduce(0, +) / Double(results.count)
    }

    private func runOne(_ text: String) async {
        isRunning = true
        defer { isRunning = false }
        let r = await parser.parse(text, streaming: streaming, usePrewarmed: usePrewarmed)
        results.insert(r, at: 0)
    }

    private func runBatch() async {
        isRunning = true
        defer { isRunning = false }
        for s in SampleSentences.all {
            let r = await parser.parse(s, streaming: streaming, usePrewarmed: usePrewarmed)
            results.insert(r, at: 0)
        }
    }
}

// MARK: - Metrics

private struct MetricsView: View {
    let m: ParseMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                stat("總時間", String(format: "%.2f s", m.totalSeconds))
                if let ttft = m.firstSnapshotSeconds {
                    stat("首個回應", String(format: "%.2f s", ttft))
                }
                stat("片段數", "\(m.snapshotCount)")
            }
            Text("\(m.streaming ? "串流" : "一次回傳") · \(m.usedPrewarmedSession ? "預熱 session" : "冷 session") · 輸入 \(m.inputCharacters) 字")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.body.monospacedDigit().weight(.semibold))
        }
    }
}

struct ContentView: View {
    // 帶 --autorun 啟動時直接切到對照測試 tab（TabView 懶載入，不切過去 .task 不會跑）
    @State private var tab = ProcessInfo.processInfo.arguments.contains("--autorun") ? 1 : 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("快速測試", systemImage: "bolt", value: 0) { QuickTestView() }
            Tab("對照測試", systemImage: "chart.bar.doc.horizontal", value: 1) { CrossTestView() }
        }
    }
}

#Preview {
    ContentView()
}
