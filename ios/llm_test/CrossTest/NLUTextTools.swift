//
//  NLUTextTools.swift
//  llm_test
//
//  純 Foundation 的工具：從凍結 prompt 檔程式化抽出帳戶／分類清單（不手打），
//  以及 R1 模式的容錯 JSON 解析（第一個 { 到最後一個 }）。
//

import Foundation

nonisolated enum PromptListExtractor {

    /// 帳戶清單：「可用帳戶清單…」到「帳戶對應提示」之間，每行「群組:名稱、名稱…」。
    /// prompt 註明「括號內為幣別」，所以名稱去掉結尾的 (USD) 之類。
    static func accounts(from prompt: String) -> [String] {
        let lines = prompt.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains("可用帳戶清單") }) else { return [] }
        var out: [String] = []
        for line in lines[(start + 1)...] {
            if line.hasPrefix("帳戶對應提示") || line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            guard let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { continue }
            let body = line[line.index(after: colon)...]
            for raw in body.components(separatedBy: "、") {
                var name = raw.trimmingCharacters(in: .whitespaces)
                if let paren = name.range(of: #"[（(][^)）]*[)）]$"#, options: .regularExpression) {
                    name.removeSubrange(paren)
                }
                if !name.isEmpty { out.append(name) }
            }
        }
        return out
    }

    /// 分類清單：「支出分類:」「收入分類:」下方每行「父>子|子|子」→ 展開成「父>子」
    static func categories(from prompt: String) -> [String] {
        let lines = prompt.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("支出分類") }) else { return [] }
        var out: [String] = []
        for line in lines[(start + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { break }
            if t.hasPrefix("收入分類") { continue }
            guard let gt = t.firstIndex(of: ">") else { break }   // 遇到規則行（沒有 >）就結束
            let parent = String(t[..<gt])
            let children = t[t.index(after: gt)...].components(separatedBy: "|")
            if children.isEmpty { out.append(parent) }
            for c in children where !c.isEmpty { out.append("\(parent)>\(c)") }
        }
        return out
    }
}

nonisolated enum R1OutputParser {

    /// 回傳 (parsed, json_valid)。抓第一個 { 到最後一個 }，parse 失敗 json_valid=false。
    static func parse(_ raw: String) -> (ParsedOutput, Bool) {
        var p = ParsedOutput()
        guard let s = raw.firstIndex(of: "{"), let e = raw.lastIndex(of: "}"), s <= e else { return (p, false) }
        let sub = String(raw[s...e])
        guard let data = sub.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (p, false) }

        p.intent = str(obj["intent"])
        let slots = obj["slots"] as? [String: Any] ?? [:]
        p.amount = num(slots["amount"])
        p.price = num(slots["price"])
        p.currency = str(slots["currency"])
        p.stock = str(slots["stock"])
        p.account = str(slots["account"])
        p.from_account = str(slots["from_account"])
        p.to_account = str(slots["to_account"])
        p.category = str(slots["category"])
        p.date = str(slots["date"])
        p.note = str(slots["note"])
        return (p, true)
    }

    static func str(_ v: Any?) -> String? {
        guard let v, !(v is NSNull) else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func num(_ v: Any?) -> Double? {
        guard let v, !(v is NSNull) else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: "")) }
        return nil
    }
}
