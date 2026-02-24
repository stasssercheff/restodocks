//
//  OrderChecklistView.swift
//  Restodocks
//
//  Заказ продуктов: продукты из номенклатуры; сохранённые заказы можно редактировать и удалять.
//

import SwiftUI

/// Строка заказа: продукт из номенклатуры + количество
struct OrderLine: Identifiable {
    let id = UUID()
    let product: Product
    var quantity: Double
    var note: String
}

extension OrderLine {
    func toPayload() -> OrderLinePayload {
        OrderLinePayload(
            productId: product.id,
            productName: product.localizedName,
            unit: product.unit,
            quantity: quantity
        )
    }

    static func fromPayload(_ p: OrderLinePayload, productStore: ProductStore) -> OrderLine {
        let product = productStore.allProducts.first { $0.id == p.productId }
            ?? Product(id: p.productId, name: p.productName, category: "misc", unit: p.unit)
        return OrderLine(product: product, quantity: p.quantity, note: "")
    }
}

struct OrderChecklistView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @StateObject private var productStore = ProductStore.shared

    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var orderLines: [OrderLine] = []
    @State private var editingOrder: SavedOrder?
    @State private var isSaving = false
    @State private var showSharePDF = false
    @State private var sharePdfURL: URL?

    /// Продукты из номенклатуры для выбора (с учётом поиска и категории)
    var productsFromNomenclature: [Product] {
        productStore.products(
            inCategory: selectedCategory,
            filteredByGluten: nil,
            lactoseFree: nil,
            searchText: searchText
        )
    }

    var categoryOptions: [String] {
        var options = [lang.t("all_categories")]
        options.append(contentsOf: productStore.categories)
        return options
    }

    private func loadOrderIntoLines(_ order: SavedOrder) {
        editingOrder = order
        orderLines = order.orderData.map { OrderLine.fromPayload($0, productStore: productStore) }
    }

    private func clearCurrentOrder() {
        editingOrder = nil
        orderLines.removeAll()
    }

    private func saveOrder() {
        guard !orderLines.isEmpty else { return }
        isSaving = true
        let payloads = orderLines.map { $0.toPayload() }
        Task { @MainActor in
            do {
                if let order = editingOrder {
                    var updated = order
                    updated.orderData = payloads
                    try await accounts.updateSavedOrder(updated)
                } else {
                    try await accounts.createSavedOrder(lines: payloads)
                }
                clearCurrentOrder()
            } catch {
                print("❌ Save order error:", error)
            }
            isSaving = false
        }
    }

    private func saveOrderAsPDF() {
        guard !orderLines.isEmpty else { return }
        let title = lang.t("order_checklist")
        guard let pdfData = OrderPDFGenerator.pdfData(
            orderLines: orderLines,
            title: title,
            date: Date(),
            productColumnTitle: lang.t("product_catalog"),
            unitColumnTitle: lang.t("unit"),
            quantityColumnTitle: lang.t("quantity")
        ) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let fileName = "order_\(formatter.string(from: Date())).pdf"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try pdfData.write(to: fileURL)
            sharePdfURL = fileURL
            showSharePDF = true
        } catch {
            print("❌ Save PDF error:", error)
        }
    }

    private func formatOrderQuantity(_ q: Double) -> String {
        if q == floor(q) { return "\(Int(q))" }
        return String(format: "%.1f", q)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker(lang.t("category"), selection: $selectedCategory) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Text(category == lang.t("all_categories") ? category : category.capitalized)
                            .tag(category == lang.t("all_categories") ? nil : category)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(lang.t("search"), text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))

            if productStore.isLoading {
                ProgressView(lang.t("loading_products"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(header: Text(lang.t("saved_orders"))) {
                        if accounts.savedOrders.isEmpty {
                            Text(lang.t("no_saved_orders"))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(accounts.savedOrders) { order in
                                Button {
                                    loadOrderIntoLines(order)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(formatOrderDate(order.createdAt))
                                                .font(.headline)
                                            Text("\(order.orderData.count) \(lang.t("products_count"))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if editingOrder?.id == order.id {
                                            Image(systemName: "pencil.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task {
                                            await accounts.deleteSavedOrder(order)
                                            if editingOrder?.id == order.id {
                                                clearCurrentOrder()
                                            }
                                        }
                                    } label: {
                                        Text(lang.t("delete"))
                                    }
                                }
                            }
                        }
                    }

                    Section(header: Text(lang.t("order_checklist"))) {
                        if orderLines.isEmpty && editingOrder == nil {
                            Text(lang.t("no_shifts"))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(orderLines) { line in
                                OrderLineRow(
                                    line: line,
                                    quantity: Binding(
                                        get: { orderLines.first(where: { $0.id == line.id })?.quantity ?? 0 },
                                        set: { newVal in
                                            if let i = orderLines.firstIndex(where: { $0.id == line.id }) {
                                                orderLines[i].quantity = newVal
                                            }
                                        }
                                    ),
                                    lang: lang,
                                    onDelete: { orderLines.removeAll { $0.id == line.id } }
                                )
                            }
                            .onDelete { indexSet in
                                orderLines.remove(atOffsets: indexSet)
                            }
                        }
                    }

                    Section(header: Text(lang.t("product_catalog"))) {
                        ForEach(productsFromNomenclature) { product in
                            Button {
                                addProductToOrder(product)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(product.localizedName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        if let unit = product.unit {
                                            Text(unit)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(lang.t("order_checklist"))
        .toolbar {
            // Leading оставляем пустым — системная стрелка «Назад» всегда активна
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    if !orderLines.isEmpty {
                        Button(lang.t("save_pdf")) {
                            saveOrderAsPDF()
                        }
                    }
                    if editingOrder != nil || !orderLines.isEmpty {
                        Button(lang.t("new_order")) {
                            clearCurrentOrder()
                        }
                    }
                    if !orderLines.isEmpty {
                        Button(lang.t("save")) {
                            saveOrder()
                        }
                        .disabled(isSaving)
                    }
                    if !orderLines.isEmpty {
                        Button(lang.t("clear")) {
                            orderLines.removeAll()
                        }
                    }
                    // Кнопка «Домой» — переход на домашний экран
                    Button {
                        popCurrentNavigationToRoot()
                    } label: {
                        Image(systemName: "house.fill")
                    }
                    .accessibilityLabel(lang.t("home"))
                }
            }
        }
        .onAppear {
            productStore.loadNomenclature()
            Task { await accounts.fetchSavedOrders() }
        }
        .refreshable {
            await accounts.fetchSavedOrders()
        }
        .sheet(isPresented: $showSharePDF) {
            if let url = sharePdfURL {
                ShareSheetView(fileURL: url) {
                    showSharePDF = false
                    try? FileManager.default.removeItem(at: url)
                    sharePdfURL = nil
                }
            }
        }
    }

    private func formatOrderDate(_ date: Date?) -> String {
        guard let d = date else { return lang.t("order") }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.locale = Locale(identifier: "ru_RU")
        return f.string(from: d)
    }

    private func addProductToOrder(_ product: Product) {
        if let i = orderLines.firstIndex(where: { $0.product.id == product.id }) {
            orderLines[i].quantity += 1
        } else {
            orderLines.append(OrderLine(product: product, quantity: 1, note: ""))
        }
    }
}

struct OrderLineRow: View {
    let line: OrderLine
    @Binding var quantity: Double
    let lang: LocalizationManager
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.product.localizedName)
                    .font(.headline)
                if let unit = line.product.unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Stepper(
                formatQuantity(quantity),
                value: $quantity,
                in: 0.1...1000,
                step: line.product.unit == "шт" ? 1 : 0.5
            )
            .labelsHidden()

            Text(formatQuantity(quantity))
                .frame(width: 56, alignment: .trailing)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    private func formatQuantity(_ q: Double) -> String {
        if q == floor(q) {
            return "\(Int(q))"
        }
        return String(format: "%.1f", q)
    }
}
