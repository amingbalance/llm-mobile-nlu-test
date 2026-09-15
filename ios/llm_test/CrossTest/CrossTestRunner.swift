//
//  CrossTestRunner.swift
//  llm_test
//
//  跨平台 NLU 對照測試 harness（照 nlu_crosstest/ios_test_design_spec.md）。
//  R1 = 純 prompt、不開 guided generation、日期交給模型。
//  R2 = DynamicGenerationSchema（enum 由 prompt 檔程式生成）+ 程式解析日期。
//  每題每模式 N 次、每次全新 session；結果寫成 spec §7 的 JSON 到 Documents。
//

import Foundation
import FoundationModels
import Network
import CryptoKit

@MainActor
@Observable
final class CrossTestRunner {

    enum Mode: String, CaseIterable, Identifiable {
        case R1, R2
        var id: String { rawValue }
        var title: String { self == .R1 ? "R1 model-only" : "R2 best-mode (guided)" }
    }

    // 素材
    private(set) var suite: TestSuite?
    private(set) var prompt = ""
    private(set) var promptSHA = ""
    private(set) var accounts: [String] = []
    private(set) var categories: [String] = []
    private(set) var loadError: String?
    private(set) var availabilityText = ""

    /// 凍結 prompt 的放置方式。spec：instructions 優先，框架不支援則前置於輸入（prepended）。
    /// input_first 是偏差變體：Apple 的語言閘門（NLLanguageRecognizer 判成印尼文）擋掉前兩種，
    /// 把輸入句放在最前面可讓偵測翻成 en 而放行；結果檔會標注。
    enum Placement: String, CaseIterable, Identifiable {
        case instructions
        case prepended
        case inputFirst = "input_first"
        case inputWrapped = "input_wrapped"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .instructions: return "instructions（spec）"
            case .prepended: return "前置於輸入（spec 備案）"
            case .inputFirst: return "輸入在前（偏差，繞語言閘門）"
            case .inputWrapped: return "輸入在前+在後（偏差，繞閘門且保留 spec 順序）"
            }
        }
    }

    // 設定
    var includeSchemaInPrompt = true
    var runsPerCase = 3
    var placement: Placement = .instructions

    // 狀態
    private(set) var isRunning = false
    private(set) var progress = ""
    private(set) var log: [String] = []
    private(set) var liveRuns: [RunRecord] = []
    private(set) var coldStartMs: Int?
    private(set) var coldStartError: String?
    private(set) var savedFiles: [URL] = []

    private let expectedPromptChars = 3434

    init() {
        load()
        refreshSavedFiles()
    }

    // MARK: - 素材載入

    func load() {
        loadError = nil
        guard let pURL = Bundle.main.url(forResource: "system_prompt_zh-TW", withExtension: "txt"),
              let tURL = Bundle.main.url(forResource: "testcases", withExtension: "json") else {
            loadError = "app bundle 裡找不到 system_prompt_zh-TW.txt / testcases.json"
            return
        }
        do {
            let pData = try Data(contentsOf: pURL)
            guard let text = String(data: pData, encoding: .utf8) else { loadError = "prompt 不是 UTF-8"; return }
            prompt = text
            promptSHA = SHA256.hash(data: pData).map { String(format: "%02x", $0) }.joined()
            suite = try JSONDecoder().decode(TestSuite.self, from: Data(contentsOf: tURL))
            accounts = PromptListExtractor.accounts(from: prompt)
            categories = PromptListExtractor.categories(from: prompt)
        } catch {
            loadError = "載入失敗：\(error)"
        }
        availabilityText = Self.describeAvailability()
    }

    var promptCharsOK: Bool { prompt.count == expectedPromptChars }
    var promptChars: Int { prompt.count }

    static func describeAvailability() -> String {
        switch SystemLanguageModel.default.availability {
        case .available: return "available"
        case .unavailable(let r):
            switch r {
            case .deviceNotEligible: return "unavailable(deviceNotEligible)"
            case .appleIntelligenceNotEnabled: return "unavailable(appleIntelligenceNotEnabled)"
            case .modelNotReady: return "unavailable(modelNotReady)"
            @unknown default: return "unavailable(unknown)"
            }
        }
    }

    // MARK: - 執行

    private var options: GenerationOptions {
        let maxTokens = max(512, suite?.decoding.maxOutputTokens ?? 512)
        return GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: maxTokens)
    }

    private func makeSession() -> LanguageModelSession {
        placement == .instructions ? LanguageModelSession(instructions: prompt) : LanguageModelSession()
    }

    private func userPrompt(_ input: String) -> String {
        switch placement {
        case .instructions: return input
        case .prepended: return prompt + "\n\n" + input
        case .inputFirst: return input + "\n\n" + prompt
        case .inputWrapped: return input + "\n\n" + prompt + "\n\n" + input
        }
    }

    private var placementNote: String {
        switch placement {
        case .instructions: return "frozen prompt as LanguageModelSession(instructions:); user turn = input only"
        case .prepended: return "no instructions; user turn = frozen prompt + blank line + input (spec fallback)"
        case .inputFirst: return "DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language"
        case .inputWrapped: return "DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim) + blank line + input. The trailing input is the spec 'prepended' order; the leading copy exists only to pass the language gate. Input therefore appears twice"
        }
    }

    private var frozenToday: Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: suite?.frozen_today ?? "2026-09-15") ?? .now
    }

    func run(modes: [Mode]) async {
        guard let suite, !isRunning else { return }
        isRunning = true
        defer { isRunning = false; progress = "完成" }
        liveRuns = []

        let reachable = await Self.networkReachable()
        addLog("網路可達：\(reachable.map(String.init) ?? "未知")（裝置端模型不走網路，僅記錄）")

        if coldStartMs == nil {
            await measureColdStart()
        } else {
            addLog("warmup 已做過（本次啟動冷啟動 \(coldStartMs!) ms）")
        }

        for mode in modes {
            let started = Date()
            var runs: [RunRecord] = []
            var schema: GenerationSchema?
            var includeSchema = includeSchemaInPrompt
            var schemaNote: String?

            if mode == .R2 {
                do {
                    schema = try makeSchema()
                } catch {
                    addLog("R2 schema 建立失敗：\(error)")
                    continue
                }
                (includeSchema, schemaNote) = await preflightR2(schema!, input: suite.cases[0].input)
            }

            for c in suite.cases {
                for r in 1...runsPerCase {
                    progress = "\(mode.rawValue)  \(c.id)  run \(r)/\(runsPerCase)"
                    let rec: RunRecord
                    if mode == .R1 {
                        rec = await runR1(c, run: r)
                    } else {
                        rec = await runR2(c, run: r, schema: schema!, includeSchema: includeSchema)
                    }
                    runs.append(rec)
                    liveRuns.append(rec)
                    addLog("\(mode.rawValue) \(c.id)#\(r) \(rec.latency_ms)ms \(rec.parsed.intent ?? "—") amt=\(rec.parsed.amount.map { Self.fmt($0) } ?? "—") \(rec.error.map { "ERR " + $0 } ?? "")")
                }
            }

            let file = ResultsFile(
                mode: mode.rawValue,
                suite_version: suite.version,
                frozen_today: suite.frozen_today,
                started_at: Self.iso8601(started),
                finished_at: Self.iso8601(.now),
                env: makeEnv(mode: mode, includeSchema: includeSchema, schemaNote: schemaNote, reachable: reachable),
                cold_start_ms: coldStartMs,
                cold_start_note: "本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次" + (coldStartError.map { "；warmup 錯誤：\($0)" } ?? ""),
                runs: runs
            )
            save(file, mode: mode)
        }
    }

    private func measureColdStart() async {
        progress = "warmup / 冷啟動量測"
        let t0 = ContinuousClock.now
        let session = makeSession()
        let warm = placement == .instructions ? "測試" : (suite?.cases.first?.input ?? "測試")
        var warmErr: String?
        do {
            _ = try await session.respond(to: userPrompt(warm), options: options)
        } catch {
            warmErr = Self.describe(error)
            addLog("warmup 錯誤：\(warmErr!)")
        }
        coldStartMs = Self.ms(since: t0)
        coldStartError = warmErr
        addLog("冷啟動 \(coldStartMs!) ms")
    }

    // R1：純字串回應
    private func runR1(_ c: TestSuite.Case, run: Int) async -> RunRecord {
        var rec = RunRecord(case_id: c.id, run: run, latency_ms: 0, first_token_ms: nil, json_valid: false, parsed: ParsedOutput(), raw_output: "", error: nil)
        let session = makeSession()
        let t0 = ContinuousClock.now
        do {
            let resp = try await session.respond(to: userPrompt(c.input), options: options)
            rec.latency_ms = Self.ms(since: t0)
            rec.raw_output = resp.content
            let (p, ok) = R1OutputParser.parse(resp.content)
            rec.parsed = p
            rec.json_valid = ok
        } catch {
            rec.latency_ms = Self.ms(since: t0)
            rec.error = Self.describe(error)
        }
        return rec
    }

    // R2：guided generation + 程式解析日期
    private func runR2(_ c: TestSuite.Case, run: Int, schema: GenerationSchema, includeSchema: Bool) async -> RunRecord {
        var rec = RunRecord(case_id: c.id, run: run, latency_ms: 0, first_token_ms: nil, json_valid: false, parsed: ParsedOutput(), raw_output: "", error: nil)
        let session = makeSession()
        let t0 = ContinuousClock.now
        do {
            let resp = try await session.respond(to: userPrompt(c.input), schema: schema, includeSchemaInPrompt: includeSchema, options: options)
            rec.latency_ms = Self.ms(since: t0)
            let gc = resp.content
            rec.raw_output = gc.jsonString
            rec.json_valid = true
            var p = ParsedOutput()
            p.intent = try? gc.value(String.self, forProperty: "intent")
            p.amount = try? gc.value(Double?.self, forProperty: "amount")
            p.price = try? gc.value(Double?.self, forProperty: "price")
            p.currency = try? gc.value(String?.self, forProperty: "currency")
            p.stock = try? gc.value(String?.self, forProperty: "stock")
            p.account = try? gc.value(String?.self, forProperty: "account")
            p.from_account = try? gc.value(String?.self, forProperty: "from_account")
            p.to_account = try? gc.value(String?.self, forProperty: "to_account")
            p.category = try? gc.value(String?.self, forProperty: "category")
            p.date_text = try? gc.value(String?.self, forProperty: "date_text")
            p.note = try? gc.value(String?.self, forProperty: "note")
            if let dt = p.date_text?.trimmingCharacters(in: .whitespacesAndNewlines), !dt.isEmpty,
               let d = ChineseDateResolver.resolve(dt, today: frozenToday) {
                p.date = Self.isoDay(d)
            }
            rec.parsed = p
        } catch {
            rec.latency_ms = Self.ms(since: t0)
            rec.error = Self.describe(error)
        }
        return rec
    }

    /// R2 預檢（不計入結果）：schema 注入 prompt 若爆 context window，改為不注入並記錄
    private func preflightR2(_ schema: GenerationSchema, input: String) async -> (Bool, String?) {
        progress = "R2 預檢"
        let session = makeSession()
        do {
            _ = try await session.respond(to: userPrompt(input), schema: schema, includeSchemaInPrompt: includeSchemaInPrompt, options: options)
            return (includeSchemaInPrompt, nil)
        } catch let e as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = e, includeSchemaInPrompt {
                addLog("R2 預檢：includeSchemaInPrompt=true 超過 context window，本輪改用 false")
                return (false, "includeSchemaInPrompt=true exceeded context window in preflight; this round ran with false")
            }
            addLog("R2 預檢錯誤：\(Self.describe(e))")
            return (includeSchemaInPrompt, "preflight error: \(Self.describe(e))")
        } catch {
            return (includeSchemaInPrompt, "preflight error: \(error)")
        }
    }

    // MARK: - Schema（enum 值域由 prompt 檔程式生成）

    private func makeSchema() throws -> GenerationSchema {
        let intent = DynamicGenerationSchema(name: "Intent", description: "意圖", anyOf: [
            "UPDATE_GOLD_PRICE", "UPDATE_STOCK_PRICE", "ADD_INCOME", "ADD_EXPENSE", "ADD_TRANSFER", "UNKNOWN",
        ])
        let currency = DynamicGenerationSchema(name: "Currency", description: "幣別", anyOf: ["TWD", "USD"])
        let account = DynamicGenerationSchema(name: "Account", description: "帳戶清單內的確切名稱", anyOf: accounts)
        let category = DynamicGenerationSchema(name: "Category", description: "分類清單內的「父>子」", anyOf: categories)
        let number = DynamicGenerationSchema(type: Double.self)
        let text = DynamicGenerationSchema(type: String.self)
        typealias P = DynamicGenerationSchema.Property

        let root = DynamicGenerationSchema(name: "NLUResult", description: "語音記帳意圖解析結果", properties: [
            P(name: "intent", description: "意圖", schema: DynamicGenerationSchema(referenceTo: "Intent")),
            P(name: "amount", description: "收入/支出/轉帳金額；沒講給 null", schema: number, isOptional: true),
            P(name: "price", description: "黃金或股票價格；沒講給 null", schema: number, isOptional: true),
            P(name: "currency", description: "幣別；沒講給 null", schema: DynamicGenerationSchema(referenceTo: "Currency"), isOptional: true),
            P(name: "stock", description: "股票名稱或代碼，照字面；沒講給 null", schema: text, isOptional: true),
            P(name: "account", description: "帳戶；對不上清單給 null", schema: DynamicGenerationSchema(referenceTo: "Account"), isOptional: true),
            P(name: "from_account", description: "轉出帳戶；對不上清單給 null", schema: DynamicGenerationSchema(referenceTo: "Account"), isOptional: true),
            P(name: "to_account", description: "轉入帳戶；對不上清單給 null", schema: DynamicGenerationSchema(referenceTo: "Account"), isOptional: true),
            P(name: "category", description: "分類；對不上清單給 null", schema: DynamicGenerationSchema(referenceTo: "Category"), isOptional: true),
            P(name: "date_text", description: "原句中的日期字面，例如「上週五」「昨天」，不要換算；沒講日期給 null", schema: text, isOptional: true),
            P(name: "note", description: "備註；沒有給 null", schema: text, isOptional: true),
        ])
        return try GenerationSchema(root: root, dependencies: [intent, currency, account, category])
    }

    // MARK: - 環境 / 存檔

    private func makeEnv(mode: Mode, includeSchema: Bool, schemaNote: String?, reachable: Bool?) -> EnvInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        let versionString = ProcessInfo.processInfo.operatingSystemVersionString
        let build = versionString.range(of: #"\(Build ([^)]+)\)"#, options: .regularExpression)
            .map { String(versionString[$0]).replacingOccurrences(of: "(Build ", with: "").replacingOccurrences(of: ")", with: "") } ?? "?"
        let machine = Self.machineIdentifier()
        return EnvInfo(
            device: "\(machine) (\(Self.marketingName(machine)))",
            chip_note: Self.chipNote(machine),
            os: "iOS \(osVersion)",
            os_build: build,
            framework: "FoundationModels (SystemLanguageModel.default, on-device)",
            sdk: (info["DTSDKName"] as? String) ?? "?",
            xcode: "\((info["DTXcode"] as? String) ?? "?") (\((info["DTXcodeBuild"] as? String) ?? "?"))",
            model_id_or_availability: "availability=\(Self.describeAvailability()); framework exposes no model version API",
            system_prompt_placement: placement.rawValue,
            placement_note: placementNote,
            system_prompt_chars: prompt.count,
            system_prompt_sha256: promptSHA,
            decoding: DecodingInfo(
                temperature: 0,
                sampling: "greedy (GenerationOptions.SamplingMode.greedy)",
                maximumResponseTokens: max(512, suite?.decoding.maxOutputTokens ?? 512),
                includeSchemaInPrompt: mode == .R2 ? includeSchema : nil,
                includeSchemaNote: mode == .R2 ? schemaNote : nil
            ),
            cloud_fallback_disabled_how: "FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run",
            network_reachable_during_run: reachable,
            enum_source: "dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)",
            accounts_count: accounts.count,
            categories_count: categories.count,
            r2_schema_omitted_fields: ["confidence", "normalized_text", "original_text"],
            r2_date_resolver: "ChineseDateResolver.swift, today fixed to \(suite?.frozen_today ?? "2026-09-15"), week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字",
            runs_per_case: runsPerCase,
            session_policy: "new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms"
        )
    }

    private func save(_ file: ResultsFile, mode: Mode) {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let data = try enc.encode(file)
            let osTag = file.env.os.replacingOccurrences(of: "iOS ", with: "iOS")
            let variant = (mode == .R2 && file.env.decoding.includeSchemaInPrompt == false) ? "_noschema" : ""
            let name = "results_\(osTag)_\(mode.rawValue)\(variant)_\(placement.rawValue)_\(Self.stamp()).json"
            let url = Self.documentsDir.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            addLog("已存檔 \(name)（\(file.runs.count) runs）")
            refreshSavedFiles()
        } catch {
            addLog("存檔失敗：\(error)")
        }
    }

    /// autorun 狀態檔（autorun_status.json，覆寫）：可用性、載入錯誤、階段
    func writeAutorunStatus(phase: String) {
        let v = ProcessInfo.processInfo.operatingSystemVersionString
        let dict: [String: Any] = [
            "phase": phase,
            "time": Self.iso8601(.now),
            "os": v,
            "availability": Self.describeAvailability(),
            "loadError": loadError ?? "",
            "promptChars": prompt.count,
            "accounts": accounts.count,
            "categories": categories.count,
            "placement": placement.rawValue,
            "includeSchemaInPrompt": includeSchemaInPrompt,
            "runsPerCase": runsPerCase,
            "progress": progress,
            "lastLog": Array(log.suffix(5)),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: Self.documentsDir.appendingPathComponent("autorun_status.json"), options: .atomic)
        }
    }

    func refreshSavedFiles() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.documentsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        savedFiles = urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func deleteFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refreshSavedFiles()
    }

    // MARK: - Helpers

    static var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func addLog(_ s: String) {
        log.append(s)
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    static func ms(since t0: ContinuousClock.Instant) -> Int {
        let d = t0.duration(to: .now).components
        return Int(d.seconds * 1000) + Int(d.attoseconds / 1_000_000_000_000_000)
    }

    static func fmt(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

    static func isoDay(_ d: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    static func iso8601(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
    static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: .now)
    }

    static func machineIdentifier() -> String {
        var sys = utsname()
        uname(&sys)
        return withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }
    static func marketingName(_ id: String) -> String {
        switch id {
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        default: return "unknown"
        }
    }
    static func chipNote(_ id: String) -> String {
        id.hasPrefix("iPhone17,") && (id.hasSuffix("1") || id.hasSuffix("2")) ? "A18 Pro" : "see device id"
    }

    static func networkReachable() async -> Bool? {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "llm_test.net"))
        try? await Task.sleep(for: .milliseconds(400))
        let status = monitor.currentPath.status
        monitor.cancel()
        return status == .satisfied
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .exceededContextWindowSize: return "exceededContextWindowSize"
            case .guardrailViolation: return "guardrailViolation"
            case .unsupportedLanguageOrLocale: return "unsupportedLanguageOrLocale"
            case .assetsUnavailable: return "assetsUnavailable"
            case .decodingFailure: return "decodingFailure"
            case .rateLimited: return "rateLimited"
            case .refusal: return "refusal"
            case .concurrentRequests: return "concurrentRequests"
            case .unsupportedGuide: return "unsupportedGuide"
            @unknown default: return "GenerationError.unknown: \(e)"
            }
        }
        return String(describing: error)
    }
}
