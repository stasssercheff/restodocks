//
//  IngredientRowView.swift
//  Restodocks
//
//  Строка таблицы ингредиентов в ТТК
//

import SwiftUI

struct IngredientRowView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var appState: AppState
    @StateObject private var productStore = ProductStore.shared

    let index: Int
    @Binding var ingredient: TTIngredient
    let onDelete: () -> Void

    @State private var showingProductPicker = false
    @State private var showingProcessPicker = false
    @State private var editingGrossWeight = false
    @State private var editingNetWeight = false
    @State private var grossWeightText = ""
    @State private var netWeightText = ""

    private var product: Product? {
        guard let productId = ingredient.productId else { return nil }
        return productStore.allProducts.first { $0.id == productId }
    }

    private var cookingProcess: CookingProcess? {
        guard let processId = ingredient.cookingProcessId else { return nil }
        return CookingProcessManager.shared.processById(processId)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Номер
            Text("\(index)")
                .frame(width: 28)
                .font(.caption)
                .foregroundColor(.secondary)

            // Наименование продукта
            Button {
                showingProductPicker = true
            } label: {
                Text(ingredient.productName.isEmpty ? lang.t("select_product") : ingredient.productName)
                    .frame(width: 100, alignment: .leading)
                    .font(.caption)
                    .foregroundColor(ingredient.productName.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            }

            // Брутто
            if editingGrossWeight {
                TextField("", text: $grossWeightText)
                    .keyboardType(.decimalPad)
                    .frame(width: 52)
                    .font(.caption)
                    .onSubmit {
                        if let value = Double(grossWeightText) {
                            var ing = ingredient
                            ing.updateGrossWeight(value, product: product, cookingProcess: cookingProcess)
                            ingredient = ing
                        }
                        editingGrossWeight = false
                    }
            } else {
                Button {
                    grossWeightText = String(format: "%.1f", ingredient.grossWeight)
                    editingGrossWeight = true
                } label: {
                    Text(String(format: "%.1f", ingredient.grossWeight))
                        .frame(width: 52)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }

            // % отхода (авто: брутто → нетто)
            Text(String(format: "%.0f", ingredient.wastePercentage))
                .frame(width: 40)
                .font(.caption)
                .foregroundColor(.secondary)

            // Нетто
            if editingNetWeight {
                TextField("", text: $netWeightText)
                    .keyboardType(.decimalPad)
                    .frame(width: 52)
                    .font(.caption)
                    .onSubmit {
                        if let value = Double(netWeightText) {
                            var ing = ingredient
                            ing.updateNetWeight(value, product: product, cookingProcess: cookingProcess)
                            ingredient = ing
                        }
                        editingNetWeight = false
                    }
            } else {
                Button {
                    netWeightText = String(format: "%.1f", ingredient.netWeight)
                    editingNetWeight = true
                } label: {
                    HStack(spacing: 2) {
                        Text(String(format: "%.1f", ingredient.netWeight))
                        if ingredient.isNetWeightManual {
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                        }
                    }
                    .frame(width: 52)
                    .font(.caption)
                    .foregroundColor(ingredient.isNetWeightManual ? .orange : .primary)
                }
            }

            // Технология приготовления
            Button {
                showingProcessPicker = true
            } label: {
                Text(cookingProcess?.localizedName ?? lang.t("select_process"))
                    .frame(width: 72)
                    .font(.caption)
                    .foregroundColor(cookingProcess == nil ? .secondary : .primary)
                    .lineLimit(1)
            }

            // Ужарка % (статистическая, из процесса)
            Text(String(format: "%.0f", ingredient.shrinkagePercentage(process: cookingProcess)))
                .frame(width: 40)
                .font(.caption)
                .foregroundColor(.secondary)

            // Выход (нетто * (1 - ужарка/100))
            Text(String(format: "%.1f", ingredient.yieldWeight(process: cookingProcess)))
                .frame(width: 52)
                .font(.caption)
                .foregroundColor(.secondary)

            // Стоимость
            Text(String(format: "%.0f", ingredient.cost))
                .frame(width: 52)
                .font(.caption)
                .foregroundColor(.secondary)

            // Кнопка удаления
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(index % 2 == 0 ? AppTheme.cardBackground : AppTheme.secondaryBackground)
        .sheet(isPresented: $showingProductPicker) {
            ProductPickerView(
                selectedProduct: product,
                onSelect: { selectedProduct in
                    ingredient.productId = selectedProduct.id
                    ingredient.productName = selectedProduct.localizedName
                    
                    var ing = ingredient
                    ing.productId = selectedProduct.id
                    ing.productName = selectedProduct.localizedName
                    let gross = ingredient.grossWeight > 0 ? ingredient.grossWeight : 100
                    ing.updateGrossWeight(gross, product: selectedProduct, cookingProcess: cookingProcess)
                    ingredient = ing
                    showingProductPicker = false
                }
            )
        }
        .sheet(isPresented: $showingProcessPicker) {
            if let prod = product {
                NavigationView {
                    List(CookingProcessManager.shared.processesForCategory(prod.category)) { process in
                        Button {
                            var ing = ingredient
                            ing.updateCookingProcess(process, product: prod)
                            ingredient = ing
                            showingProcessPicker = false
                        } label: {
                            HStack {
                                Text(process.localizedName)
                                Spacer()
                                if process.id == ingredient.cookingProcessId {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(AppTheme.primary)
                                }
                            }
                        }
                    }
                    .navigationTitle(lang.t("select_cooking_process"))
                }
            }
        }
        .onChange(of: ingredient.grossWeight) {
            if !ingredient.isNetWeightManual, let prod = product {
                var ing = ingredient
                ing.updateGrossWeight(ingredient.grossWeight, product: prod, cookingProcess: cookingProcess)
                ingredient = ing
            }
        }
    }
}