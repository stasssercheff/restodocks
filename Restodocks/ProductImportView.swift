//
//  ProductImportView.swift
//  Restodocks
//
//  Загрузка продуктов из файла: TXT, RTF, CSV, XLSX, DOCX и др.
//

import SwiftUI
import UniformTypeIdentifiers

struct ProductImportView: View {
    @EnvironmentObject var lang: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var productStore = ProductStore.shared

    @State private var importedRows: [ProductImportRow] = []
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var selectedCategory = "misc"
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            Group {
                if isProcessing {
                    ProgressView(lang.t("loading_products"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(err)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if importedRows.isEmpty {
                    VStack(spacing: 20) {
                        Text(lang.t("import_products_hint"))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding()
                        Text(lang.t("import_formats"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button(lang.t("open_file")) {
                            showFileImporter = true
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section(header: Text("\(importedRows.count) \(lang.t("products_count"))")) {
                            Picker(lang.t("category"), selection: $selectedCategory) {
                                Text("misc").tag("misc")
                                ForEach(productStore.categories, id: \.self) { cat in
                                    Text(cat.capitalized).tag(cat)
                                }
                            }
                            ForEach(importedRows) { row in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.name)
                                            .font(.headline)
                                        HStack(spacing: 8) {
                                            if let p = row.price {
                                                Text(String(format: "%.2f", p))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            if let curr = row.currency {
                                                Text(curr)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            if let u = row.unit {
                                                Text(u)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(lang.t("upload_products"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !importedRows.isEmpty {
                        Button(lang.t("save")) {
                            addToNomenclature()
                            dismiss()
                        }
                    } else if !isProcessing, errorMessage == nil, importedRows.isEmpty {
                        Button(lang.t("open_file")) {
                            showFileImporter = true
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: ProductImportParser.supportedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileResult(result)
            }
        }
    }

    private func handleFileResult(_ result: Result<[URL], Error>) {
        isProcessing = true
        errorMessage = nil
        Task {
            defer { await MainActor.run { isProcessing = false } }
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    await MainActor.run { errorMessage = "Нет доступа к файлу" }
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                let ext = url.pathExtension
                let localRows = try ProductImportParser.parse(data: data, fileExtension: ext)
                guard !localRows.isEmpty else {
                    await MainActor.run { errorMessage = lang.t("no_shifts") }
                    return
                }
                let rawRows = localRows.map { row in
                    if let p = row.price {
                        return "\(row.name)\t\(p)"
                    }
                    return row.name
                }
                do {
                    let aiItems = try await AiProductImportService.shared.parseProductList(
                        rows: rawRows,
                        source: ext
                    )
                    let aiRows: [ProductImportRow] = aiItems.map { item in
                        ProductImportRow(
                            name: item.name,
                            price: item.price,
                            category: nil,
                            currency: item.currency,
                            unit: item.unit
                        )
                    }
                    await MainActor.run { importedRows = aiRows }
                } catch {
                    await MainActor.run {
                        importedRows = localRows
                        errorMessage = nil
                    }
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func addToNomenclature() {
        for row in importedRows {
            let product = Product(
                name: row.name,
                category: selectedCategory,
                basePrice: row.price,
                currency: row.currency ?? "RUB",
                unit: row.unit ?? "шт"
            )
            productStore.addProduct(product)
        }
    }
}
