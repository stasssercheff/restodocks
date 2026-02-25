//
//  ProductImportParser.swift
//  Restodocks
//
//  Парсинг файлов загрузки продуктов: txt, rtf, csv, xlsx, docx и др.
//

import Foundation
import UniformTypeIdentifiers

/// Одна строка импорта: название продукта, цена, валюта, единица (из ИИ-анализа или локального парсера).
struct ProductImportRow: Identifiable {
    let id = UUID()
    var name: String
    var price: Double?
    var category: String?
    var currency: String? = nil
    var unit: String? = nil
}

enum ProductImportParser {

    static let supportedExtensions = ["txt", "rtf", "csv", "xlsx", "xls", "doc", "docx", "numbers", "pages"]

    static var supportedContentTypes: [UTType] {
        [
            .plainText,
            .rtf,
            .commaSeparatedText,
            .spreadsheet,
            UTType(filenameExtension: "xlsx") ?? .spreadsheet,
            UTType(filenameExtension: "xls") ?? .data,
            .document,
            UTType(filenameExtension: "docx") ?? .document,
            UTType(filenameExtension: "doc") ?? .data,
            UTType(filenameExtension: "numbers") ?? .data,
            UTType(filenameExtension: "pages") ?? .data,
        ].compactMap { $0 }
    }

    /// Парсинг данных файла по расширению.
    static func parse(data: Data, fileExtension: String) throws -> [ProductImportRow] {
        let ext = fileExtension.lowercased().replacingOccurrences(of: ".", with: "")
        switch ext {
        case "txt", "text":
            return try parsePlainText(data: data)
        case "rtf":
            return try parseRTF(data: data)
        case "csv":
            return try parseCSV(data: data)
        case "xlsx", "xls", "docx", "doc", "numbers", "pages":
            return try parseOfficeLike(data: data, ext: ext)
        default:
            return try parsePlainText(data: data)
        }
    }

    // MARK: - TXT
    private static func parsePlainText(data: Data) throws -> [ProductImportRow] {
        let encoding: [String.Encoding] = [.utf8, .windowsCP1251, .isoLatin1]
        var str: String?
        for enc in encoding {
            str = String(data: data, encoding: enc)
            if str != nil { break }
        }
        guard let text = str else {
            throw NSError(domain: "ProductImportParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать текст (кодировка)"])
        }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { ProductImportRow(name: $0, price: nil, category: nil) }
    }

    // MARK: - RTF
    private static func parseRTF(data: Data) throws -> [ProductImportRow] {
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        guard let attr = try? NSAttributedString(data: data, options: opts, documentAttributes: nil) else {
            throw NSError(domain: "ProductImportParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ошибка чтения RTF"])
        }
        let text = attr.string
        let dataUtf8 = text.data(using: .utf8) ?? Data()
        return try parsePlainText(data: dataUtf8)
    }

    // MARK: - CSV
    private static func parseCSV(data: Data) throws -> [ProductImportRow] {
        let encoding: [String.Encoding] = [.utf8, .windowsCP1251, .isoLatin1]
        var text: String?
        for enc in encoding {
            text = String(data: data, encoding: enc)
            if text != nil { break }
        }
        guard let csv = text else {
            throw NSError(domain: "ProductImportParser", code: 3, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать CSV"])
        }
        var rows: [ProductImportRow] = []
        let lines = csv.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let cells = splitCSVLine(trimmed)
            let name = cells.first?.trimmingCharacters(in: .whitespaces) ?? ""
            if name.isEmpty { continue }
            var price: Double?
            if cells.count > 1 {
                let priceStr = cells[1]
                    .replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: " ", with: "")
                let filtered = priceStr.filter { $0.isNumber || $0 == "." }
                price = Double(filtered)
            }
            rows.append(ProductImportRow(name: name, price: price, category: nil))
        }
        return rows
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if (ch == "," || ch == ";" || ch == "\t") && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    // MARK: - XLSX, DOCX, XLS, DOC, Numbers, Pages — через системное извлечение текста или подсказка
    private static func parseOfficeLike(data: Data, ext: String) throws -> [ProductImportRow] {
        if ext == "xlsx" || ext == "docx" {
            if data.count >= 4 && data[0] == 0x50 && data[1] == 0x4B {
                if let rows = try? parseZIPBasedFile(data: data, ext: ext) {
                    return rows
                }
            }
        }
        if let str = String(data: data, encoding: .utf8), str.count > 10 {
            let lineCount = str.components(separatedBy: .newlines).count
            if lineCount > 1 {
                return try parsePlainText(data: data)
            }
        }
        let formatList = "XLSX, XLS, DOC, DOCX, Numbers, Pages"
        throw NSError(domain: "ProductImportParser", code: 6, userInfo: [
            NSLocalizedDescriptionKey: "Файл .\(ext) не удалось обработать. Сохраните список продуктов в формате CSV или TXT (одна строка — один продукт) и загрузите снова. Поддерживаются напрямую: TXT, RTF, CSV."
        ])
    }

    /// Минимальный разбор ZIP (только store, без deflate) для xlsx/docx.
    private static func parseZIPBasedFile(data: Data, ext: String) throws -> [ProductImportRow]? {
        var offset = 0
        var sharedStrings: [String] = []
        var sheetRows: [[String]] = []
        var docxText: String?

        while offset + 30 <= data.count {
            let sig = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
            guard sig == 0x04034B50 else { offset += 1; continue }
            let comp = UInt16(data[offset + 8]) | (UInt16(data[offset + 9]) << 8)
            let nameLen = Int(data[offset + 26]) | (Int(data[offset + 27]) << 8)
            let extraLen = Int(data[offset + 28]) | (Int(data[offset + 29]) << 8)
            let compSize = Int(data[offset + 18]) | (Int(data[offset + 19]) << 8) | (Int(data[offset + 20]) << 16) | (Int(data[offset + 21]) << 24)
            let nameStart = offset + 30
            guard nameStart + nameLen + extraLen <= data.count else { break }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLen))
            let path = String(data: nameData, encoding: .utf8) ?? ""
            let contentStart = nameStart + nameLen + extraLen
            let contentEnd = min(contentStart + compSize, data.count)
            let content = contentEnd > contentStart ? data.subdata(in: contentStart..<contentEnd) : Data()

            if comp == 0, content.count < 10_000_000 {
                let pathLower = path.lowercased()
                if pathLower.contains("sharedstrings.xml") {
                    sharedStrings = extractSharedStringsFromXLSX(content)
                }
                if pathLower.contains("sheet") && pathLower.hasSuffix(".xml") {
                    sheetRows = parseSheetXML(content, sharedStrings: sharedStrings)
                    if !sheetRows.isEmpty { break }
                }
                if ext == "docx" && pathLower.hasPrefix("word/document") {
                    docxText = extractTextFromDocxXML(content)
                    if docxText != nil { break }
                }
            }

            offset = contentEnd
        }

        if !sheetRows.isEmpty {
            var result: [ProductImportRow] = []
            for row in sheetRows.dropFirst() {
                let name = row.first?.trimmingCharacters(in: .whitespaces) ?? ""
                if name.isEmpty { continue }
                var price: Double?
                if row.count > 1 { price = Double(row[1].replacingOccurrences(of: ",", with: ".")) }
                result.append(ProductImportRow(name: name, price: price, category: nil))
            }
            return result
        }
        if let text = docxText, !text.isEmpty {
            let dataUtf8 = text.data(using: .utf8) ?? Data()
            return try? parsePlainText(data: dataUtf8)
        }
        return nil
    }

    private static func extractSharedStringsFromXLSX(_ data: Data) -> [String] {
        guard let str = String(data: data, encoding: .utf8) else { return [] }
        let pattern = "<t[^>]*>([^<]*)</t>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(str.startIndex..., in: str)
        let matches = regex.matches(in: str, range: range)
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: str) else { return nil }
            return String(str[r])
        }
    }

    private static func parseSheetXML(_ data: Data, sharedStrings: [String]) -> [[String]] {
        guard let str = String(data: data, encoding: .utf8) else { return [] }
        var rows: [[String]] = []
        let rowRegex = try? NSRegularExpression(pattern: "<row [^>]*>")
        let cellRegex = try? NSRegularExpression(pattern: "<c[^>]*>.*?</c>", options: .dotMatchesLineSeparators)
        let vRegex = try? NSRegularExpression(pattern: "<v>([^<]*)</v>")
        let tRegex = try? NSRegularExpression(pattern: "<t>([^<]*)</t>")
        let rowMatches = rowRegex?.matches(in: str, range: NSRange(str.startIndex..., in: str)) ?? []
        for rowMatch in rowMatches {
            guard let rowRange = Range(rowMatch.range, in: str) else { continue }
            let rowStr = String(str[rowRange])
            let cellMatches = cellRegex?.matches(in: rowStr, range: NSRange(rowStr.startIndex..., in: rowStr)) ?? []
            var cells: [String] = []
            for cellMatch in cellMatches {
                guard let cellRange = Range(cellMatch.range, in: rowStr) else { continue }
                let cellStr = String(rowStr[cellRange])
                if let vMatch = vRegex?.firstMatch(in: cellStr, range: NSRange(cellStr.startIndex..., in: cellStr)),
                   vMatch.numberOfRanges > 1, let r = Range(vMatch.range(at: 1), in: cellStr) {
                    let v = String(cellStr[r])
                    if cellStr.contains(" t=\"s\"") {
                        let idx = Int(v) ?? 0
                        cells.append(idx < sharedStrings.count ? sharedStrings[idx] : v)
                    } else {
                        cells.append(v)
                    }
                } else if let tMatch = tRegex?.firstMatch(in: cellStr, range: NSRange(cellStr.startIndex..., in: cellStr)),
                          tMatch.numberOfRanges > 1, let r = Range(tMatch.range(at: 1), in: cellStr) {
                    cells.append(String(cellStr[r]))
                }
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        return rows
    }

    private static func extractTextFromDocxXML(_ data: Data) -> String? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        let pattern = "<w:t[^>]*>([^<]*)</w:t>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(str.startIndex..., in: str)
        let matches = regex.matches(in: str, range: range)
        let parts = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: str) else { return nil }
            return String(str[r])
        }
        return parts.joined()
    }
}
