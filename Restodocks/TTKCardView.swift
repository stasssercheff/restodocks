//
//  TTKCardView.swift
//  Restodocks
//
//  Карточка ТТК для поваров: блюдо (пересчёт по порциям) или полуфабрикат (пропорциональный пересчёт).
//

import SwiftUI

struct TTKCardView: View {
    @EnvironmentObject var lang: LocalizationManager
    @StateObject private var productStore = ProductStore.shared

    let card: TechCard

    /// Блюдо: выбранное количество порций (целое).
    @State private var portions: Int = 1
    /// Полуфабрикат: множитель масштаба. 1 = базовая рецептура; при изменении любого ингредиента пересчитываются все.
    @State private var scaleFactor: Double = 1.0
    /// Полуфабрикат: отображаемые количества [index] = scaled (не сохраняются в карточку).
    @State private var scaledQuantities: [Int: Double] = [:]

    private let manager = CookingProcessManager.shared

    private var title: String {
        card.localizedDishName
    }

    private var baseQuantities: [Double] {
        card.ingredients.map { $0.grossWeight }
    }

    private var baseTotalYield: Double {
        card.totalYield(manager: manager)
    }

    /// Блюдо: количество на одну порцию (рецепт на basePortions).
    private func quantityPerPortion(at index: Int) -> Double {
        guard index < card.ingredients.count, card.basePortions > 0 else { return 0 }
        return baseQuantities[index] / Double(card.basePortions)
    }

    /// Блюдо: отображаемое количество при выбранных порциях.
    private func displayedQuantityDish(at index: Int) -> Double {
        quantityPerPortion(at: index) * Double(portions)
    }

    /// Полуфабрикат: отображаемое количество (базовое × scaleFactor или из scaledQuantities).
    private func displayedQuantitySemi(at index: Int) -> Double {
        if let s = scaledQuantities[index], s >= 0 { return s }
        guard index < baseQuantities.count else { return 0 }
        return baseQuantities[index] * scaleFactor
    }

    /// Полуфабрикат: при изменении ингредиента index на newValue пересчитываем scaleFactor и все scaledQuantities.
    private func applySemiFinishedEdit(index: Int, newValue: Double) {
        guard index < baseQuantities.count, baseQuantities[index] > 0, newValue >= 0 else { return }
        let k = newValue / baseQuantities[index]
        scaleFactor = k
        var next: [Int: Double] = [:]
        for i in baseQuantities.indices {
            next[i] = baseQuantities[i] * k
        }
        scaledQuantities = next
    }

    /// Сброс полуфабриката к базе (инструмент не меняет карточку).
    private func resetSemiFinishedScaling() {
        scaleFactor = 1.0
        scaledQuantities = [:]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Заголовок (RU / EN при наличии)
                Text(title)
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.leading)

                if card.cardType == .dish {
                    dishSection
                } else {
                    semiFinishedSection
                }
            }
            .padding()
        }
        .navigationTitle(title)
    }

    // MARK: - Блюдо: порции, таблица, «N порций»

    private var dishSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(lang.t("portions"))
                    .font(.subheadline)
                Stepper("\(portions)", value: $portions, in: 1...999)
                    .labelsHidden()
                Text("\(portions)")
                    .frame(minWidth: 36, alignment: .trailing)
                    .font(.headline)
            }
            .padding(8)
            .background(AppTheme.secondaryBackground)
            .cornerRadius(8)

            cardTable(
                quantities: (0..<card.ingredients.count).map { displayedQuantityDish(at: $0) },
                editable: false
            )

            HStack {
                Text(String(format: lang.t("portions_count"), portions))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(portions)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.secondaryBackground)
            .cornerRadius(8)
        }
    }

    // MARK: - Полуфабрикат: таблица с редактируемыми количествами, «Итого», комментарий

    private var semiFinishedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if scaleFactor != 1.0 {
                Button {
                    resetSemiFinishedScaling()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text(lang.t("reset_scaling"))
                    }
                    .font(.caption)
                }
            }

            cardTable(
                quantities: (0..<card.ingredients.count).map { displayedQuantitySemi(at: $0) },
                editable: true,
                onQuantityChange: applySemiFinishedEdit
            )

            let total = baseTotalYield * scaleFactor
            HStack {
                Text(lang.t("summary"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f", total))
                    .font(.subheadline)
                    .bold()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.secondaryBackground)
            .cornerRadius(8)

            if !card.comment.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.t("comment"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(card.comment)
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.cardBackground)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Общая таблица: №, Ингредиент, Шт/гр, Описание

    private func cardTable(
        quantities: [Double],
        editable: Bool,
        onQuantityChange: ((Int, Double) -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text("#")
                        .frame(width: 28, alignment: .leading)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(lang.t("product_name"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(lang.t("qty_pcs_g"))
                        .frame(width: 64, alignment: .trailing)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.secondaryBackground)

                ForEach(Array(card.ingredients.enumerated()), id: \.element.id) { index, ing in
                    let qty = index < quantities.count ? quantities[index] : 0
                    TTKCardRowView(
                        index: index + 1,
                        ingredient: ing,
                        quantity: qty,
                        editable: editable,
                        product: product(for: ing),
                        onQuantityChange: onQuantityChange.map { f in { f(index, $0) } }
                    )
                }
            }
            .background(AppTheme.cardBackground)
            .cornerRadius(12)

            VStack(alignment: .leading, spacing: 8) {
                Text(lang.t("description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(card.localizedTechnology())
                    .font(.subheadline)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
        }
    }

    private func product(for ing: TTIngredient) -> Product? {
        guard let id = ing.productId else { return nil }
        return productStore.allProducts.first { $0.id == id }
    }
}

// MARK: - Строка карточки

private struct TTKCardRowView: View {
    @EnvironmentObject var lang: LocalizationManager
    let index: Int
    let ingredient: TTIngredient
    let quantity: Double
    let editable: Bool
    let product: Product?
    let onQuantityChange: ((Double) -> Void)?

    @State private var editText: String = ""
    @FocusState private var focused: Bool

    private var unitLabel: String {
        (product?.unit).map { u in
            if u == "шт" || u.lowercased().contains("pcs") { return "шт" }
            return "г"
        } ?? "г"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("\(index)")
                .frame(width: 28, alignment: .leading)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(ingredient.productName)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.subheadline)
                .lineLimit(2)

            if editable, let apply = onQuantityChange {
                TextField("", text: $editText)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .font(.subheadline)
                    .onAppear { editText = formatQty(quantity) }
                    .onChange(of: quantity) { _ in
                        if !focused { editText = formatQty(quantity) }
                    }
                    .onSubmit { commitEdit(apply) }
                    .onChange(of: focused) { _ in
                        if !focused { commitEdit(apply) }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(lang.t("done")) {
                                focused = false
                                commitEdit(apply)
                            }
                        }
                    }
            } else {
                Text(formatQty(quantity))
                    .frame(width: 64, alignment: .trailing)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(index % 2 == 0 ? Color.clear : AppTheme.secondaryBackground.opacity(0.5))
    }

    private func commitEdit(_ apply: (Double) -> Void) {
        let s = editText.replacingOccurrences(of: ",", with: ".")
        if let v = Double(s), v >= 0 {
            apply(v)
        }
    }

    private func formatQty(_ q: Double) -> String {
        if q.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", q)
        }
        return String(format: "%.1f", q)
    }
}
