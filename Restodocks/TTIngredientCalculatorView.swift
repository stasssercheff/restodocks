//
//  TTIngredientCalculatorView.swift
//  Restodocks
//
//  Калькулятор ингредиентов для ТТК с учетом кулинарной обработки
//

import SwiftUI

struct TTIngredientCalculatorView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var appState: AppState

    let product: Product
    @State private var selectedProcess: CookingProcess? = CookingProcessManager.shared.processes.first { $0.name == "raw" }
    @State private var weight: Double = 100.0
    @State private var calculatedIngredient: TTIngredient?

    private var processedProduct: ProcessedProduct? {
        guard let process = selectedProcess else { return nil }
        return process.apply(to: product, weight: weight)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Заголовок
                Text(lang.t("ingredient_calculator"))
                    .font(.title2)
                    .bold()

                // Информация о продукте
                VStack(alignment: .leading, spacing: 12) {
                    Text(product.localizedName)
                        .font(.title3)
                        .bold()

                    Text(product.category.capitalized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Базовая информация о питательности
                    if let calories = product.calories,
                       let protein = product.protein,
                       let fat = product.fat,
                       let carbs = product.carbs {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lang.t("base_nutrition") + " (на 100г):")
                                .font(.headline)

                            HStack(spacing: 16) {
                                Text("\(lang.t("calories_abbr")): \(Int(calories))")
                                Text("\(lang.t("protein_abbr")): \(protein)g")
                                Text("\(lang.t("fat_abbr")): \(fat)g")
                                Text("\(lang.t("carbs_abbr")): \(carbs)g")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(12)

                // Выбор кулинарного процесса
                CookingProcessPicker(
                    productCategory: product.category,
                    selectedProcess: $selectedProcess
                )

                // Ввод веса
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.t("weight") + " (г)")
                        .font(.headline)

                    TextField("100", value: $weight, format: .number)
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(AppTheme.cardBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                }

                // Результаты расчета
                if let processed = processedProduct {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(lang.t("processing_results"))
                            .font(.headline)

                        VStack(spacing: 8) {
                            // Вес до и после обработки
                            HStack {
                                Text(lang.t("original_weight") + ": \(String(format: "%.1f", weight))г")
                                Spacer()
                                Text(lang.t("final_weight") + ": \(String(format: "%.1f", processed.finalWeight))г")
                            }
                            .font(.caption)

                            Text(lang.t("weight_loss") + ": \(String(format: "%.1f", weight - processed.finalWeight))г (\(String(format: "%.1f", selectedProcess?.weightLossPercentage ?? 0))%)")
                                .font(.caption)
                                .foregroundColor(.orange)

                            Divider()

                            // Итоговые питательные вещества
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lang.t("final_nutrition") + ":")
                                    .font(.subheadline)
                                    .bold()

                                HStack(spacing: 16) {
                                    Text("\(lang.t("calories_abbr")): \(String(format: "%.1f", processed.totalCalories))")
                                    Text("\(lang.t("protein_abbr")): \(String(format: "%.1f", processed.totalProtein))g")
                                    Text("\(lang.t("fat_abbr")): \(String(format: "%.1f", processed.totalFat))g")
                                    Text("\(lang.t("carbs_abbr")): \(String(format: "%.1f", processed.totalCarbs))g")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }

                            // Стоимость
                            if let basePrice = product.basePrice {
                                Divider()

                                HStack {
                                    Text(lang.t("cost") + ":")
                                    Spacer()
                                    Text("\(String(format: "%.2f", (processed.finalWeight / 1000.0) * basePrice)) \(appState.defaultCurrency)")
                                        .foregroundColor(.green)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                }

                // Кнопка применения
                if let process = selectedProcess {
                    Button {
                        calculatedIngredient = TTIngredient(
                            product: product,
                            cookingProcess: process,
                            grossWeight: weight,
                            defaultCurrency: appState.defaultCurrency
                        )
                    } label: {
                        Text(lang.t("apply_to_recipe"))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.primary)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(lang.t("ingredient_calculator"))
        .onAppear {
            // Установить сырое состояние по умолчанию
            selectedProcess = CookingProcessManager.shared.processes.first { $0.name == "raw" }
        }
    }
}