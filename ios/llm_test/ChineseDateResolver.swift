//
//  ChineseDateResolver.swift
//  llm_test
//
//  把中文的相對／絕對日期描述（「昨晚」「上週五」「9/10」「上個月 28 號」）換算成實際日期。
//  模型只負責照抄句中的日期原文，換算交給這裡，避免小模型算錯。
//

import Foundation

enum ChineseDateResolver {

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2   // 週一為一週開始（台灣習慣）
        return c
    }

    /// 回傳 nil 代表看不懂；呼叫端自行決定 fallback（通常是今天）
    static func resolve(_ raw: String, today: Date = .now) -> Date? {
        let cal = calendar
        let day = cal.startOfDay(for: today)
        let text = normalize(raw)
        if text.isEmpty { return day }

        // 1. 完整日期：2026/9/10、2026-09-10、2026年9月10日
        if let m = text.firstMatch(of: #/(\d{4})[/\-年](\d{1,2})[/\-月](\d{1,2})[日號]?/#) {
            return cal.date(from: DateComponents(year: Int(m.1), month: Int(m.2), day: Int(m.3)))
        }

        // 2. 月/日：9/10、9-10、9月10日、九月十號
        if let m = text.firstMatch(of: #/(\d{1,2})[/\-月](\d{1,2})[日號]?/#) {
            let year = cal.component(.year, from: day)
            guard var d = cal.date(from: DateComponents(year: year, month: Int(m.1), day: Int(m.2))) else { return nil }
            // 記帳幾乎不會記未來很久的事：若超過今天 7 天，視為去年
            if d > cal.date(byAdding: .day, value: 7, to: day)! {
                d = cal.date(byAdding: .year, value: -1, to: d)!
            }
            return d
        }

        // 3. 上個月 28 號 / 這個月 5 日 / 下月 1 號
        if let m = text.firstMatch(of: #/(上上|上|這|本|下)個?月(\d{1,2})[日號]/#) {
            let offset = monthOffset(String(m.1))
            guard let base = cal.date(byAdding: .month, value: offset, to: day) else { return nil }
            var comps = cal.dateComponents([.year, .month], from: base)
            comps.day = Int(m.2)
            return cal.date(from: comps)
        }

        // 4. 單獨的「28 號」：這個月；若還沒到就當上個月
        if let m = text.firstMatch(of: #/^(\d{1,2})[日號]$/#) {
            var comps = cal.dateComponents([.year, .month], from: day)
            comps.day = Int(m.1)
            guard var d = cal.date(from: comps) else { return nil }
            if d > day { d = cal.date(byAdding: .month, value: -1, to: d)! }
            return d
        }

        // 5. 上週五 / 這禮拜三 / 下星期一 / 週五 / 星期天
        if let m = text.firstMatch(of: #/(上上|上|這|本|下)?(週|星期|禮拜)([一二三四五六日天])/#) {
            let targetWeekday = weekdayIndex(String(m.3))          // 1 = 週一 … 7 = 週日
            let todayWeekday = (cal.component(.weekday, from: day) + 5) % 7 + 1
            let monday = cal.date(byAdding: .day, value: -(todayWeekday - 1), to: day)!
            if let prefix = m.1 {
                let weeks = weekOffset(String(prefix))
                return cal.date(byAdding: .day, value: weeks * 7 + (targetWeekday - 1), to: monday)
            }
            // 沒有前綴：最近一次（含今天）的那個星期幾
            var d = cal.date(byAdding: .day, value: targetWeekday - 1, to: monday)!
            if d > day { d = cal.date(byAdding: .day, value: -7, to: d)! }
            return d
        }

        // 6. 上週 / 上禮拜（沒指定星期幾）
        if text.contains("上上週") || text.contains("上上禮拜") || text.contains("上上星期") {
            return cal.date(byAdding: .day, value: -14, to: day)
        }
        if text.contains("上週") || text.contains("上禮拜") || text.contains("上星期") {
            return cal.date(byAdding: .day, value: -7, to: day)
        }

        // 7. N 天前 / N 天後
        if let m = text.firstMatch(of: #/(\d+)天(前|後)/#) {
            let n = Int(m.1)!
            return cal.date(byAdding: .day, value: m.2 == "前" ? -n : n, to: day)
        }

        // 8. 關鍵字
        let keywords: [(String, Int)] = [
            ("大前天", -3), ("前天", -2), ("前晚", -2),
            ("昨", -1),
            ("後天", 2), ("明", 1),
            ("今", 0), ("剛", 0), ("現在", 0), ("稍早", 0),
        ]
        for (k, offset) in keywords where text.contains(k) {
            return cal.date(byAdding: .day, value: offset, to: day)
        }

        return nil
    }

    // MARK: - Helpers

    /// 去空白、全形轉半形、中文數字轉阿拉伯數字（只處理日期會用到的 1~99）
    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: " ", with: "")
        t = t.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? t
        t = t.replacingOccurrences(of: "周", with: "週")
        t = t.replacingOccurrences(of: "拜", with: "禮拜").replacingOccurrences(of: "禮禮拜", with: "禮拜")
        t = replaceChineseNumerals(in: t)
        return t
    }

    /// 把「二十八號」「十月三日」裡的中文數字換成阿拉伯數字；星期幾的「一~日」不動
    private static func replaceChineseNumerals(in s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "[一二三四五六七八九十兩]+(?=[月號日天])") else { return s }
        let ns = s as NSString
        var out = s
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let token = ns.substring(with: m.range)
            // 避免把「星期一」的「一」吃掉：前面若是 週/星期/禮拜 就跳過
            let before = ns.substring(to: m.range.location)
            if before.hasSuffix("週") || before.hasSuffix("星期") || before.hasSuffix("禮拜") { continue }
            if let n = chineseToInt(token) {
                out = (out as NSString).replacingCharacters(in: m.range, with: String(n))
            }
        }
        return out
    }

    static func chineseToInt(_ s: String) -> Int? {
        let digits: [Character: Int] = ["一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if s == "十" { return 10 }
        var result = 0, current = 0
        for ch in s {
            if ch == "十" {
                result += (current == 0 ? 1 : current) * 10
                current = 0
            } else if let d = digits[ch] {
                current = d
            } else {
                return nil
            }
        }
        return result + current
    }

    private static func weekdayIndex(_ ch: String) -> Int {
        switch ch {
        case "一": return 1
        case "二": return 2
        case "三": return 3
        case "四": return 4
        case "五": return 5
        case "六": return 6
        default: return 7   // 日 / 天
        }
    }

    private static func weekOffset(_ prefix: String) -> Int {
        switch prefix {
        case "上上": return -2
        case "上": return -1
        case "下": return 1
        default: return 0    // 這 / 本
        }
    }

    private static func monthOffset(_ prefix: String) -> Int {
        switch prefix {
        case "上上": return -2
        case "上": return -1
        case "下": return 1
        default: return 0
        }
    }
}
