//
//  ProductPickerView.swift
//  Restodocks
//
//  Выбор продукта из каталога с поиском
//

import SwiftUI

struct ProductPickerView: View {
    @EnvironmentObject var lang: LocalizationManager
    @StateObject private var productStore = ProductStore.shared

    let selectedProduct: Product?
    let onSelect: (Product) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @Environment(\.dismiss) var dismiss

    var filteredProducts: [Product] {
        productStore.products(
            inCategory: selectedCategory,
            searchText: searchText
        )
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Поиск и фильтр категории
                VStack(spacing: 12) {
                    // Поиск
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField(lang.t("search"), text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                    // Фильтр категории
                    Picker(lang.t("category"), selection: $selectedCategory) {
                        Text(lang.t("all_categories")).tag(nil as String?)
                        ForEach(productStore.categories, id: \.self) { category in
                            Text(category.capitalized).tag(category as String?)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding()

                // Список продуктов
                if productStore.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredProducts) { product in
                        Button {
                            onSelect(product)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(product.localizedName)
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text(product.category.capitalized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    // КБЖУ
                                    if let calories = product.calories,
                                       let protein = product.protein,
                                       let fat = product.fat,
                                       let carbs = product.carbs {
                                        Text("\(Int(calories)) ккал, Б:\(protein) Ж:\(fat) У:\(carbs)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                if selectedProduct?.id == product.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppTheme.primary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(lang.t("select_product"))
            .navigationBarItems(
                trailing: Button(lang.t("cancel")) {
                    dismiss()
                }
            )
        }
    }
}