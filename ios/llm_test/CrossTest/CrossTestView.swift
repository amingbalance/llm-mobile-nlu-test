//
//  CrossTestView.swift
//  llm_test
//

import SwiftUI

struct CrossTestView: View {
    @State private var runner = CrossTestRunner()

    var body: some View {
        NavigationStack {
            Form {
                materialsSection
                environmentSection
                settingsSection
                runSection
                if !runner.liveRuns.isEmpty { liveSection }
                filesSection
            }
            .navigationTitle("跨平台 NLU 對照")
            .task { await autorunIfRequested() }
        }
    }

    /// 從 Mac 用 devicectl 啟動時可帶參數無人值守執行：
    ///   --autorun R1,R2   --runs 3   --no-schema-in-prompt
    private func autorunIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--autorun"), i + 1 < args.count else { return }
        let modes = args[i + 1].split(separator: ",").compactMap { CrossTestRunner.Mode(rawValue: String($0)) }
        if let j = args.firstIndex(of: "--runs"), j + 1 < args.count, let n = Int(args[j + 1]) { runner.runsPerCase = max(1, min(5, n)) }
        if args.contains("--no-schema-in-prompt") { runner.includeSchemaInPrompt = false }
        if let k = args.firstIndex(of: "--placement"), k + 1 < args.count, let p = CrossTestRunner.Placement(rawValue: args[k + 1]) { runner.placement = p }
        guard !modes.isEmpty else { return }
        // 先寫一份狀態檔，讓 Mac 端看得到 app 為什麼沒跑（例如 OS 升級後模型重新下載中）
        runner.writeAutorunStatus(phase: "start")
        // 模型未就緒（modelNotReady 等）時每 10 秒重查，最多等 15 分鐘
        var waited = 0
        while !canRun && waited < 900 {
            try? await Task.sleep(for: .seconds(10))
            waited += 10
            runner.load()
            if waited % 60 == 0 { runner.writeAutorunStatus(phase: "waiting \(waited)s") }
        }
        runner.writeAutorunStatus(phase: canRun ? "running" : "gave_up")
        guard canRun else { return }
        await runner.run(modes: modes)
        runner.writeAutorunStatus(phase: "finished")
    }

    // MARK: 素材

    private var materialsSection: some View {
        Section("凍結素材（bundle 內）") {
            if let err = runner.loadError {
                Label(err, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
            row("prompt 字數", "\(runner.promptChars)（預期 3434）", ok: runner.promptCharsOK)
            row("prompt SHA-256", String(runner.promptSHA.prefix(16)) + "…", ok: nil)
            row("帳戶 enum", "\(runner.accounts.count)（預期 21）", ok: runner.accounts.count == 21)
            row("分類 enum", "\(runner.categories.count)（預期 65）", ok: runner.categories.count == 65)
            if let s = runner.suite {
                row("testcases", "\(s.version)，\(s.cases.count) 題，今天凍結 \(s.frozen_today)", ok: true)
            }
        }
    }

    private var environmentSection: some View {
        Section("環境") {
            row("裝置", CrossTestRunner.machineIdentifier() + " · " + CrossTestRunner.marketingName(CrossTestRunner.machineIdentifier()), ok: nil)
            row("OS", ProcessInfo.processInfo.operatingSystemVersionString, ok: nil)
            row("模型", runner.availabilityText, ok: runner.availabilityText == "available")
            if let ms = runner.coldStartMs { row("冷啟動", "\(ms) ms", ok: nil) }
        }
    }

    private var settingsSection: some View {
        Section("設定") {
            Picker("prompt 放置", selection: $runner.placement) {
                ForEach(CrossTestRunner.Placement.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.navigationLink)
            .disabled(runner.isRunning)
            Toggle("R2：schema 注入 prompt（includeSchemaInPrompt）", isOn: $runner.includeSchemaInPrompt)
                .disabled(runner.isRunning)
            Stepper("每題次數：\(runner.runsPerCase)（spec 規定 3）", value: $runner.runsPerCase, in: 1...5)
                .disabled(runner.isRunning)
        }
    }

    private var runSection: some View {
        Section("執行") {
            HStack {
                Button("R1") { Task { await runner.run(modes: [.R1]) } }
                    .buttonStyle(.bordered)
                Button("R2") { Task { await runner.run(modes: [.R2]) } }
                    .buttonStyle(.bordered)
                Button("R1 + R2") { Task { await runner.run(modes: [.R1, .R2]) } }
                    .buttonStyle(.borderedProminent)
                Spacer()
                if runner.isRunning { ProgressView() }
            }
            .disabled(!canRun)
            if !runner.progress.isEmpty {
                Text(runner.progress).font(.callout.monospacedDigit())
            }
            if !runner.log.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(runner.log.suffix(10).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced()).lineLimit(2)
                    }
                }
            }
        }
    }

    private var liveSection: some View {
        Section("本輪結果（✓ 對 / ✗ 錯 / △ 沒講日期卻填今天）") {
            ForEach(runner.liveRuns.reversed()) { r in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("\(r.case_id) #\(r.run)").font(.footnote.bold())
                        Text(r.parsed.intent ?? "—").font(.footnote)
                        Spacer()
                        Text("\(r.latency_ms) ms").font(.footnote.monospacedDigit())
                    }
                    if let c = runner.suite?.cases.first(where: { $0.id == r.case_id }) {
                        Text(QuickScorer.summary(r, expected: c.expected, frozenToday: runner.suite?.frozen_today ?? ""))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let e = r.error {
                        Text(e).font(.caption2).foregroundStyle(.red)
                    } else if !r.json_valid {
                        Text("json_valid=false").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var filesSection: some View {
        Section("結果檔（Documents，可用 Finder / 檔案 app 取出）") {
            if runner.savedFiles.isEmpty {
                Text("尚無").foregroundStyle(.secondary)
            }
            ForEach(runner.savedFiles, id: \.self) { url in
                HStack {
                    Text(url.lastPathComponent).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
                .swipeActions {
                    Button(role: .destructive) { runner.deleteFile(url) } label: { Label("刪除", systemImage: "trash") }
                }
            }
        }
    }

    private var canRun: Bool {
        !runner.isRunning && runner.loadError == nil && runner.suite != nil && runner.availabilityText == "available"
    }

    private func row(_ title: String, _ value: String, ok: Bool?) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).font(.callout)
            if let ok {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? Color.green : Color.red)
            }
        }
    }
}

// MARK: - 手機上即時看的簡易評分（正式評分由 tools/score.py 做）

nonisolated enum QuickScorer {
    static func summary(_ r: RunRecord, expected: TestSuite.Case.Expected, frozenToday: String) -> String {
        var parts: [String] = []
        let gotIntent = r.parsed.intent ?? "null"
        parts.append("intent\(gotIntent == expected.intent ? "✓" : "✗(\(gotIntent))")")
        for key in expected.slots.keys.sorted() {
            let want = expected.slots[key]!
            let got = r.parsed.value(for: key)
            if matches(got, want) {
                parts.append("\(key)✓")
            } else if key == "date", want == .null, got == .string(frozenToday) {
                parts.append("date△")
            } else {
                parts.append("\(key)✗(\(got.display))")
            }
        }
        return parts.joined(separator: " ")
    }

    static func matches(_ a: JSONValue, _ b: JSONValue) -> Bool {
        switch (a, b) {
        case (.number(let x), .number(let y)): return abs(x - y) < 1e-6
        case (.string(let x), .string(let y)): return x.trimmingCharacters(in: .whitespaces) == y.trimmingCharacters(in: .whitespaces)
        case (.null, .null): return true
        default: return a == b
        }
    }
}

#Preview {
    CrossTestView()
}
