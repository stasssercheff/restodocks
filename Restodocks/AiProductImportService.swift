//
//  AiProductImportService.swift
//  Restodocks
//
//  Вызов Supabase Edge Function ai-parse-product-list для полного ИИ-анализа загрузок:
//  название продукта (с исправлением опечаток), цена, валюта, единица измерения.
//  Валюта определяется из текста, по userLocale или по IP (на сервере).
//

import Foundation
import Supabase

/// Результат ИИ-анализа одной строки импорта
struct AiParsedProductItem: Identifiable {
    let id = UUID()
    let name: String
    let price: Double?
    let unit: String?
    let currency: String?
}

/// Результат вызова ai-parse-product-list
struct AiParseProductListResponse: Decodable {
    let items: [AiParsedProductItemRaw]?
    let defaultCurrency: String?
    let error: String?
}

struct AiParsedProductItemRaw: Decodable {
    let name: String
    let price: Double?
    let unit: String?
    let currency: String?
}

struct AiParseRequestBody: Encodable {
    var rows: [String]?
    var text: String?
    var source: String?
    var hintCurrency: String?
    var userLocale: String?
}

final class AiProductImportService {

    static let shared = AiProductImportService()

    private let client = SupabaseManager.shared.client

    private init() {}

    /// Полный ИИ-анализ сырых строк: извлечение названия (с исправлением опечаток), цены, валюты, единицы.
    /// - Parameters:
    ///   - rows: массив строк (из файла) или nil
    ///   - text: весь текст (если rows пустой)
    ///   - source: подсказка источника (например, "csv", "xlsx")
    /// - Returns: распознанные продукты или пустой массив при ошибке
    func parseProductList(
        rows: [String]? = nil,
        text: String? = nil,
        source: String? = nil
    ) async throws -> [AiParsedProductItem] {
        var body = AiParseRequestBody()
        body.rows = rows
        body.text = text
        body.source = source
        body.userLocale = Locale.current.identifier

        let options = FunctionInvokeOptions(body: body)
        let decoded: AiParseProductListResponse = try await client.functions.invoke(
            "ai-parse-product-list",
            options: options
        )

        if let err = decoded.error, !err.isEmpty {
            throw NSError(domain: "AiProductImport", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
        }

        let defaultCurr = decoded.defaultCurrency ?? "RUB"
        let rawItems = decoded.items ?? []
        return rawItems.map { raw in
            AiParsedProductItem(
                name: raw.name,
                price: raw.price,
                unit: raw.unit,
                currency: raw.currency ?? defaultCurr
            )
        }
    }
}
