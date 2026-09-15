//
//  CrossTestModels.swift
//  llm_test
//
//  跨平台 NLU 對照測試的資料模型：testcases.json 輸入、每次執行記錄、結果檔（對應 spec §7）。
//

import Foundation

// MARK: - 通用 JSON 值（testcases.json 的 expected slots 型別不固定）

nonisolated enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case object([String: JSONValue])
    case array([JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        }
    }

    var display: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .object, .array: return "…"
        }
    }
}

// MARK: - testcases.json

nonisolated struct TestSuite: Decodable, Sendable {
    struct Decoding: Decodable, Sendable {
        let temperature: Double
        let topK: Int
        let maxOutputTokens: Int
    }
    struct Case: Decodable, Identifiable, Sendable {
        struct Expected: Decodable, Sendable {
            let intent: String
            let slots: [String: JSONValue]
        }
        let id: String
        let input: String
        let expected: Expected
        let notes: String?
    }
    let version: String
    let frozen_today: String
    let system_prompt_file: String
    let decoding: Decoding
    let cases: [Case]
}

// MARK: - 解析後的輸出（spec §7 parsed 欄位）

nonisolated struct ParsedOutput: Codable, Equatable, Sendable {
    var intent: String?
    var amount: Double?
    var price: Double?
    var currency: String?
    var stock: String?
    var account: String?
    var from_account: String?
    var to_account: String?
    var category: String?
    var date: String?
    var note: String?
    /// R2 才有：模型抄下的日期字面，程式據此算出 date
    var date_text: String?

    init() {}

    // 手寫 encode：nil 也要輸出成 null（spec 範例所有欄位都出現）
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(intent, forKey: .intent)
        try c.encode(amount, forKey: .amount)
        try c.encode(price, forKey: .price)
        try c.encode(currency, forKey: .currency)
        try c.encode(stock, forKey: .stock)
        try c.encode(account, forKey: .account)
        try c.encode(from_account, forKey: .from_account)
        try c.encode(to_account, forKey: .to_account)
        try c.encode(category, forKey: .category)
        try c.encode(date, forKey: .date)
        try c.encode(note, forKey: .note)
        try c.encode(date_text, forKey: .date_text)
    }

    /// 給評分用：以欄位名取值
    func value(for key: String) -> JSONValue {
        func s(_ v: String?) -> JSONValue { v.map { .string($0) } ?? .null }
        func n(_ v: Double?) -> JSONValue { v.map { .number($0) } ?? .null }
        switch key {
        case "intent": return s(intent)
        case "amount": return n(amount)
        case "price": return n(price)
        case "currency": return s(currency)
        case "stock": return s(stock)
        case "account": return s(account)
        case "from_account": return s(from_account)
        case "to_account": return s(to_account)
        case "category": return s(category)
        case "date": return s(date)
        case "note": return s(note)
        default: return .null
        }
    }
}

// MARK: - 每次執行

nonisolated struct RunRecord: Codable, Identifiable, Sendable {
    var id: String { "\(case_id)-\(run)" }
    var case_id: String
    var run: Int
    var latency_ms: Int
    var first_token_ms: Int?
    var json_valid: Bool
    var parsed: ParsedOutput
    var raw_output: String
    var error: String?
}

// MARK: - 結果檔

nonisolated struct DecodingInfo: Codable, Sendable {
    var temperature: Double
    var sampling: String
    var maximumResponseTokens: Int
    var includeSchemaInPrompt: Bool?
    var includeSchemaNote: String?
}

nonisolated struct EnvInfo: Codable, Sendable {
    var device: String
    var chip_note: String
    var os: String
    var os_build: String
    var framework: String
    var sdk: String
    var xcode: String
    var model_id_or_availability: String
    var system_prompt_placement: String
    var placement_note: String
    var system_prompt_chars: Int
    var system_prompt_sha256: String
    var decoding: DecodingInfo
    var cloud_fallback_disabled_how: String
    var network_reachable_during_run: Bool?
    var enum_source: String
    var accounts_count: Int
    var categories_count: Int
    var r2_schema_omitted_fields: [String]
    var r2_date_resolver: String
    var runs_per_case: Int
    var session_policy: String
}

nonisolated struct ResultsFile: Codable, Sendable {
    var mode: String                 // R1 / R2
    var suite_version: String
    var frozen_today: String
    var started_at: String
    var finished_at: String
    var env: EnvInfo
    var cold_start_ms: Int?
    var cold_start_note: String
    var runs: [RunRecord]
}
