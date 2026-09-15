//
//  ExpenseParser.swift
//  llm_test
//
//  使用 Apple Foundation Models（iOS 26 裝置端 LLM）把自然語言消費描述解析成結構化記帳資料，
//  並量測解析速度。
//

import Foundation
import FoundationModels

// MARK: - 模型直接產生的結構（Guided Generation）

@Generable(description: "從一句中文消費描述解析出來的記帳資料")
struct ExpenseDraft {
    @Guide(description: "付款方式，只能是卡片或支付工具名稱，照句中原文填，例如「北辰卡」「青松卡」「現金」「Line Pay」「悠遊卡」。句中沒提到付款方式就填「無」，不要用品項或用途代替")
    var paymentMethod: String

    @Guide(description: "消費金額（新台幣整數）。中文數字要換成阿拉伯數字：一百二=120、兩百五=250、三百六=360、一千二=1200", .minimum(0))
    var amount: Int

    @Guide(description: "消費類別", .anyOf(ExpenseCategory.all))
    var category: String

    @Guide(description: "句中描述日期的原文，逐字照抄、不要換算，例如「昨晚」「前天」「上週五」「9/10」「上個月 28 號」。句中沒提到日期就填空字串")
    var dateText: String

    @Guide(description: "備註：店家、品項或用途名稱，例如「摩斯」「全聯」「電影票」「水費」。不要包含金額、日期和付款方式")
    var note: String
}

enum ExpenseCategory {
    static let all = ["早餐", "午餐", "晚餐", "宵夜", "飲料", "交通", "購物", "娛樂", "醫療", "居家", "其他"]
}

// MARK: - 解析後的結果

struct ExpenseRecord: Equatable {
    var paymentMethod: String?
    var amount: Int
    var category: String
    var date: String        // yyyyMMdd
    var dateText: String    // 模型抄下來的日期原文（空字串 = 句中沒提）
    var dateResolved: Bool  // false = 程式看不懂 dateText，退回今天
    var note: String
}

struct ParseMetrics {
    var usedPrewarmedSession: Bool
    var streaming: Bool
    var firstSnapshotSeconds: Double?   // 串流時第一個 partial 回來的時間（TTFT）
    var totalSeconds: Double
    var snapshotCount: Int
    var inputCharacters: Int
}

struct ParseResult: Identifiable {
    let id = UUID()
    let input: String
    let record: ExpenseRecord?
    let error: String?
    let metrics: ParseMetrics
}

// MARK: - Parser

@MainActor
@Observable
final class ExpenseParser {
    enum Availability: Equatable {
        case checking
        case available
        case unavailable(String)
    }

    private(set) var availability: Availability = .checking
    private(set) var isPrewarming = false

    /// 事先建立並 prewarm 的 session，下一次 parse 直接用
    private var readySession: LanguageModelSession?
    private var readySessionPrewarmed = false

    init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        switch SystemLanguageModel.default.availability {
        case .available:
            availability = .available
        case .unavailable(let reason):
            let text: String
            switch reason {
            case .deviceNotEligible: text = "此裝置不支援 Apple Intelligence"
            case .appleIntelligenceNotEnabled: text = "請到「設定 > Apple Intelligence 與 Siri」開啟 Apple Intelligence"
            case .modelNotReady: text = "模型尚未下載完成，請稍後再試"
            @unknown default: text = "模型無法使用（未知原因）"
            }
            availability = .unavailable(text)
        }
    }

    // MARK: Session

    static func instructions(today: Date = .now) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_TW")
        df.dateFormat = "yyyy-MM-dd EEEE"
        let todayText = df.string(from: today)
        return """
        你是記帳助理。使用者會用中文描述一筆消費，請把它解析成結構化資料。
        今天是 \(todayText)。

        規則：
        - amount 只填數字，不含貨幣符號；中文數字換成阿拉伯數字。
        - paymentMethod 照句中原文，例如「刷青松卡」填「青松卡」、「用現金」填「現金」；沒提到填「無」。
        - dateText 只抄句中的日期詞，不要自己推算日期。
        - 類別對應：早上/早餐→早餐；中午/午餐/便當→午餐；晚上/晚餐/晚飯/火鍋→晚餐；宵夜→宵夜；咖啡/拿鐵/手搖/飲料→飲料；捷運/公車/高鐵/計程車/加油/停車→交通；衣服/超市/全聯/買菜/日用品→購物；電影/遊戲/演唱會→娛樂；看醫生/藥/診所→醫療；水費/電費/瓦斯/房租/網路費/管理費→居家。
        - note 只填店家或品項名稱，簡短即可。
        """
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Self.instructions())
    }

    /// 預先準備下一個 session 並 prewarm，讓下一次解析不用付模型載入成本
    func prepareNextSession() {
        guard availability == .available else { return }
        let session = makeSession()
        readySession = session
        readySessionPrewarmed = true
        isPrewarming = true
        session.prewarm()
        isPrewarming = false
    }

    // MARK: Parse

    func parse(_ text: String, streaming: Bool, usePrewarmed: Bool) async -> ParseResult {
        let session: LanguageModelSession
        let prewarmed: Bool
        if usePrewarmed, let ready = readySession {
            session = ready
            prewarmed = readySessionPrewarmed
            readySession = nil
        } else {
            session = makeSession()
            prewarmed = false
        }

        let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 200)
        let prompt = "請解析這句話：「\(text)」"
        let start = ContinuousClock.now
        var firstSnapshot: Duration?
        var snapshotCount = 0
        var draft: ExpenseDraft?
        var errorText: String?

        do {
            if streaming {
                let stream = session.streamResponse(to: prompt, generating: ExpenseDraft.self, options: options)
                for try await _ in stream {
                    snapshotCount += 1
                    if firstSnapshot == nil { firstSnapshot = start.duration(to: .now) }
                }
                draft = try await stream.collect().content
            } else {
                draft = try await session.respond(to: prompt, generating: ExpenseDraft.self, options: options).content
                snapshotCount = 1
            }
        } catch let error as LanguageModelSession.GenerationError {
            errorText = describe(error)
        } catch {
            errorText = error.localizedDescription
        }

        let total = start.duration(to: .now)
        let metrics = ParseMetrics(
            usedPrewarmedSession: prewarmed,
            streaming: streaming,
            firstSnapshotSeconds: firstSnapshot.map(seconds),
            totalSeconds: seconds(total),
            snapshotCount: snapshotCount,
            inputCharacters: text.count
        )

        // 這個 session 已含上一輪對話，丟掉並準備下一個乾淨的 session
        if usePrewarmed { prepareNextSession() }

        return ParseResult(
            input: text,
            record: draft.map { Self.resolve($0) },
            error: errorText,
            metrics: metrics
        )
    }

    // MARK: Helpers

    static func resolve(_ draft: ExpenseDraft, today: Date = .now) -> ExpenseRecord {
        let out = DateFormatter()
        out.dateFormat = "yyyyMMdd"

        let dateText = draft.dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = ChineseDateResolver.resolve(dateText, today: today)

        let method = draft.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        let noMethod = !looksLikePaymentMethod(method)

        return ExpenseRecord(
            paymentMethod: noMethod ? nil : method,
            amount: draft.amount,
            category: draft.category,
            date: out.string(from: resolved ?? today),
            dateText: dateText,
            dateResolved: resolved != nil,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// 模型找不到付款方式時偶爾會亂塞（例如「繳水費」），只接受看起來像支付工具的字
    static func looksLikePaymentMethod(_ s: String) -> Bool {
        if s.isEmpty || ["無", "沒有", "未知", "null", "none", "nil"].contains(s.lowercased()) { return false }
        let lower = s.lowercased()
        let hints = ["卡", "現金", "pay", "支付", "悠遊", "一卡通", "街口", "轉帳", "匯款", "刷", "信用", "金融", "行動", "錢包", "點數", "禮券", "儲值"]
        return hints.contains { lower.contains($0) }
    }

    private func seconds(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    private func describe(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize: return "超過 context window"
        case .guardrailViolation: return "被安全機制擋下（guardrail）"
        case .unsupportedLanguageOrLocale: return "不支援的語言"
        case .assetsUnavailable: return "模型資源不可用"
        case .decodingFailure: return "結構化輸出解碼失敗"
        case .rateLimited: return "被限流，稍後再試"
        case .refusal: return "模型拒絕回答"
        case .concurrentRequests: return "同一 session 有並行請求"
        case .unsupportedGuide: return "不支援的 Guide"
        @unknown default: return "未知錯誤：\(error.localizedDescription)"
        }
    }
}

// MARK: - 測試句

enum SampleSentences {
    static let all: [String] = [
        "我昨晚用北辰卡花了 180 買摩斯當晚餐",
        "今天中午現金 120 吃便當",
        "早上用 Line Pay 買了 55 元的拿鐵",
        "前天搭高鐵到台中花了 700，刷南星卡",
        "剛剛在全聯買菜 860 元，用悠遊卡付",
        "9/10 看電影 320 東海卡",
        "昨天加油 1200 北辰卡",
        "宵夜買鹹酥雞 150 現金",
        "上週五晚上跟同事吃火鍋，一百二，刷青松卡",
        "兩百五買了一件T恤，用現金",
        "上個月 28 號繳水費 三百六",
    ]
}
