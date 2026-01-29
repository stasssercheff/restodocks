//
//  TechCardEditorView.swift
//  Restodocks
//
//  Редактор технологической карты (ТТК)
//

import SwiftUI

struct TechCardEditorView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var appState: AppState
    @StateObject private var productStore = ProductStore.shared

    @State private var dishName = ""
    @State private var category = "main"
    @State private var portionWeight: Double = 0
    @State private var yield: Double = 0
    @State private var ingredients: [TTIngredient] = []
    @State private var technology: String = ""
    @State private var technologyLocalized: [String: String] = [:]
    @State private var comment: String = ""
    @State private var cardType: TechCardType = .dish
    @State private var basePortions: Int = 1
    @State private var showingProductPicker = false
    @State private var selectedIngredientIndex: Int?
    @State private var translateTargetLang: String?
    @State private var showingTranslateSheet = false

    private static let supportedLanguageCodes = ["ru", "en", "es", "de", "fr"]

    let categories: [(String, String)] = [
        ("main", "category_main"),
        ("appetizer", "category_appetizer"),
        ("salad", "category_salad"),
        ("soup", "category_soup"),
        ("dessert", "category_dessert"),
        ("drink", "category_drink")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Заголовок и основная информация
                VStack(alignment: .leading, spacing: 16) {
                    TextField(lang.t("dish_name"), text: $dishName)
                        .font(.title2)
                        .bold()

                    Picker(lang.t("category"), selection: $category) {
                        ForEach(categories, id: \.0) { cat in
                            Text(lang.t(cat.1)).tag(cat.0)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker(lang.t("card_type"), selection: $cardType) {
                        Text(lang.t("card_type_dish")).tag(TechCardType.dish)
                        Text(lang.t("card_type_semi_finished")).tag(TechCardType.semiFinished)
                    }
                    .pickerStyle(.segmented)

                    if cardType == .dish {
                        HStack {
                            Text(lang.t("portions"))
                            Stepper("\(basePortions)", value: $basePortions, in: 1...999)
                                .labelsHidden()
                            Text("\(basePortions)")
                                .frame(minWidth: 32, alignment: .trailing)
                        }
                    }

                    if cardType == .semiFinished {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lang.t("comment"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(text: $comment)
                                .frame(minHeight: 44)
                        }
                    }
                }
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(12)

                // Таблица ингредиентов
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.t("ingredients"))
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                    // Заголовки таблицы (как в образце: продукт, брутто, % отхода, нетто, способ, ужарка %, выход, стоимость)
                    HStack(spacing: 6) {
                        Text("#")
                            .frame(width: 28)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lang.t("product_name"))
                            .frame(width: 100, alignment: .leading)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lang.t("gross"))
                            .frame(width: 52)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lang.t("waste_percent"))
                            .frame(width: 40)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lang.t("net"))
                            .frame(width: 52)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lang.t("process"))
                            .frame(width: 72)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lang.t("shrinkage_percent"))
                            .frame(width: 40)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lang.t("yield"))
                            .frame(width: 52)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lang.t("cost"))
                            .frame(width: 52)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppTheme.secondaryBackground)

                    // Строки ингредиентов
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        IngredientRowView(
                            index: index + 1,
                            ingredient: Binding(
                                get: { ingredients[index] },
                                set: { ingredients[index] = $0 }
                            ),
                            onDelete: {
                                ingredients.remove(at: index)
                            }
                        )
                    }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Кнопка добавления ингредиента
                    Button {
                        addNewIngredient()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(lang.t("add_ingredient"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.secondaryBackground)
                        .foregroundColor(AppTheme.primary)
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }

                // Технология (шаги приготовления)
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang.t("technology"))
                        .font(.headline)
                    TextEditor(text: $technology)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(AppTheme.secondaryBackground)
                        .cornerRadius(8)
                    HStack(spacing: 8) {
                        Text(lang.t("translate_to"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(Self.supportedLanguageCodes, id: \.self) { code in
                            if code != lang.currentLang {
                                Button {
                                    translateTargetLang = code
                                    showingTranslateSheet = true
                                } label: {
                                    Text(lang.t("lang_\(code)"))
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.secondaryBackground)
                                        .cornerRadius(6)
                                }
                                .disabled(technology.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(12)

                // Итоговая информация: вес выхода, КБЖУ, лактоза/глютен
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.t("summary"))
                        .font(.headline)

                    VStack(spacing: 8) {
                        HStack {
                            Text(lang.t("total_gross_weight") + ":")
                            Spacer()
                            Text(String(format: "%.1f г", totalGrossWeight))
                                .bold()
                        }
                        HStack {
                            Text(lang.t("total_net_weight") + ":")
                            Spacer()
                            Text(String(format: "%.1f г", totalNetWeight))
                                .bold()
                        }
                        HStack {
                            Text(lang.t("output_weight") + ":")
                            Spacer()
                            Text(String(format: "%.1f г", totalYield))
                                .bold()
                        }

                        Divider()

                        HStack {
                            Text(lang.t("total_calories") + ":")
                            Spacer()
                            Text(String(format: "%.1f ккал", totalCalories))
                                .bold()
                                .foregroundColor(.orange)
                        }
                        HStack {
                            Text(lang.t("total_protein") + ":")
                            Spacer()
                            Text(String(format: "%.1f г", totalProtein))
                                .bold()
                        }
                        HStack {
                            Text(lang.t("total_fat") + ":")
                            Spacer()
                            Text(String(format: "%.1f г", totalFat))
                                .bold()
                        }
                        HStack {
                            Text(lang.t("total_carbs") + ":")
                            Spacer()
                            Text(String(format: "%.1f г", totalCarbs))
                                .bold()
                        }

                        Divider()

                        HStack {
                            Text(lang.t("total_cost") + ":")
                            Spacer()
                            Text(String(format: "%.2f %@", totalCost, appState.defaultCurrency))
                                .bold()
                                .foregroundColor(.green)
                        }

                        Divider()

                        // Лактоза / глютен по ингредиентам
                        if dishContainsLactose || dishContainsGluten {
                            if dishContainsLactose {
                                HStack {
                                    Text(lang.t("dish_contains_lactose"))
                                        .font(.subheadline)
                                    Spacer()
                                }
                            }
                            if dishContainsGluten {
                                HStack {
                                    Text(lang.t("dish_contains_gluten"))
                                        .font(.subheadline)
                                    Spacer()
                                }
                            }
                        } else {
                            HStack {
                                Text(lang.t("no_lactose_gluten"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(12)

                // Кнопка сохранения
                PrimaryButton(title: lang.t("save_tech_card")) {
                    saveTechCard()
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle(lang.t("create_tech_card"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    TTKCardView(card: buildCurrentCard())
                } label: {
                    Text(lang.t("view_card"))
                }
                .disabled(dishName.isEmpty)
            }
        }
        .sheet(isPresented: $showingProductPicker) {
            ProductPickerView(
                selectedProduct: nil,
                onSelect: { product in
                    if let index = selectedIngredientIndex {
                        updateIngredientProduct(at: index, product: product)
                    }
                    showingProductPicker = false
                }
            )
        }
        .sheet(isPresented: $showingTranslateSheet, onDismiss: {
            translateTargetLang = nil
        }) {
            if let target = translateTargetLang {
                TechnologyTranslationView(
                    sourceText: technology,
                    sourceLang: lang.currentLang.isEmpty ? "ru" : lang.currentLang,
                    targetLang: target,
                    onComplete: { translated in
                        technologyLocalized[target] = translated
                        showingTranslateSheet = false
                    },
                    onCancel: { showingTranslateSheet = false }
                )
                .environmentObject(lang)
            }
        }
    }

    private var totalGrossWeight: Double {
        ingredients.reduce(0) { $0 + $1.grossWeight }
    }

    private var totalNetWeight: Double {
        ingredients.reduce(0) { $0 + $1.netWeight }
    }

    private var totalCalories: Double {
        ingredients.reduce(0) { $0 + $1.finalCalories }
    }

    private var totalProtein: Double {
        ingredients.reduce(0) { $0 + $1.finalProtein }
    }

    private var totalFat: Double {
        ingredients.reduce(0) { $0 + $1.finalFat }
    }

    private var totalCarbs: Double {
        ingredients.reduce(0) { $0 + $1.finalCarbs }
    }

    private var totalCost: Double {
        ingredients.reduce(0) { $0 + $1.cost }
    }

    private var totalYield: Double {
        let m = CookingProcessManager.shared
        return ingredients.reduce(0) { acc, ing in
            acc + ing.yieldWeight(process: ing.process(from: m))
        }
    }

    private var dishContainsLactose: Bool {
        ingredients.contains { ing in
            guard let id = ing.productId else { return false }
            let p = productStore.allProducts.first { $0.id == id }
            return p?.containsLactose == true
        }
    }

    private var dishContainsGluten: Bool {
        ingredients.contains { ing in
            guard let id = ing.productId else { return false }
            let p = productStore.allProducts.first { $0.id == id }
            return p?.containsGluten == true
        }
    }

    private func addNewIngredient() {
        let newIngredient = TTIngredient(
            product: nil,
            cookingProcess: nil,
            grossWeight: 0,
            netWeight: nil,
            defaultCurrency: appState.defaultCurrency
        )
        ingredients.append(newIngredient)
        selectedIngredientIndex = ingredients.count - 1
        showingProductPicker = true
    }

    private func updateIngredientProduct(at index: Int, product: Product) {
        guard index < ingredients.count else { return }
        
        let currentIngredient = ingredients[index]
        let process = CookingProcessManager.shared.processById(currentIngredient.cookingProcessId ?? UUID())
        
        var updated = TTIngredient(
            product: product,
            cookingProcess: process,
            grossWeight: currentIngredient.grossWeight > 0 ? currentIngredient.grossWeight : 100,
            netWeight: currentIngredient.isNetWeightManual ? currentIngredient.netWeight : nil,
            defaultCurrency: appState.defaultCurrency
        )
        
        // Сохранить ручной ввод нетто, если был
        if currentIngredient.isNetWeightManual {
            updated.isNetWeightManual = true
        }
        
        ingredients[index] = updated
    }

    private func saveTechCard() {
        // TODO: Сохранить ТТК в Core Data или JSON (включая technology, totalYield, lactose/gluten)
        print("💾 Сохранение ТТК: \(dishName)")
        print("📊 Ингредиентов: \(ingredients.count)")
        print("⚖️ Вес выхода: \(totalYield) г, нетто: \(totalNetWeight) г")
        print("💰 Общая стоимость: \(totalCost) \(appState.defaultCurrency)")
        if !technology.isEmpty { print("📝 Технология: \(technology.prefix(80))...") }
    }

    private func buildCurrentCard() -> TechCard {
        var local: [String: String] = [:]
        if !lang.currentLang.isEmpty {
            local[lang.currentLang] = dishName
        }
        return TechCard(
            dishName: dishName,
            dishNameLocalized: local,
            category: category,
            portionWeight: portionWeight,
            yield: yield,
            ingredients: ingredients,
            technology: technology,
            technologyLocalized: technologyLocalized,
            comment: comment,
            cardType: cardType,
            basePortions: basePortions
        )
    }
}