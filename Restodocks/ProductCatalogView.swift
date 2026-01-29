// ProductCatalogView.swift
import SwiftUI

struct ProductCatalogView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var appState: AppState
    @StateObject private var productStore = ProductStore.shared

    let department: String
    /// Если задан, используется как navigationTitle (напр. «Номенклатура»).
    var titleOverride: String? = nil

    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var glutenFreeOnly = false
    @State private var lactoseFreeOnly = false
    @State private var showFilters = false
    @State private var showingAddProduct = false
    @State private var newProduct = Product(name: "", category: "misc")

    init(department: String = "kitchen", titleOverride: String? = nil) {
        self.department = department
        self.titleOverride = titleOverride
        _productStore = StateObject(wrappedValue: ProductStore.shared)
    }

    var filteredProducts: [Product] {
        productStore.products(
            inCategory: selectedCategory,
            filteredByGluten: glutenFreeOnly ? true : nil,
            lactoseFree: lactoseFreeOnly ? true : nil,
            searchText: searchText
        )
    }

    var categoryOptions: [String] {
        var options = [lang.t("all_categories")]
        options.append(contentsOf: productStore.categories)
        return options
    }

    var body: some View {
        NavigationStack {
            VStack {
                // Search and filters
                VStack(spacing: 12) {
                    // Category picker
                    Picker(lang.t("category"), selection: $selectedCategory) {
                        ForEach(categoryOptions, id: \.self) { category in
                            Text(category == lang.t("all_categories") ? category : category.capitalized)
                                .tag(category == lang.t("all_categories") ? nil : category)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                    .padding(.horizontal)

                    // Search field
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
                    .padding(.horizontal)

                    if showFilters {
                        HStack(spacing: 16) {
                            Toggle("🌾 Без глютена", isOn: $glutenFreeOnly)
                                .toggleStyle(.button)
                                .foregroundColor(glutenFreeOnly ? .green : .secondary)

                            Toggle("🥛 Без лактозы", isOn: $lactoseFreeOnly)
                                .toggleStyle(.button)
                                .foregroundColor(lactoseFreeOnly ? .blue : .secondary)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)

                // Product list
                if productStore.isLoading {
                    ProgressView(lang.t("loading_products"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = productStore.error {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("\(lang.t("loading_error")): \(error.localizedDescription)")
                            .multilineTextAlignment(.center)
                            .padding()
                        Button(lang.t("retry")) {
                            productStore.loadProducts()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredProducts) { product in
                        NavigationLink {
                            ProductDetailView(product: product)
                        } label: {
                            ProductRowView(product: product)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle(titleOverride != nil ? lang.t(titleOverride!) : lang.t("product_catalog"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if appState.canManageSchedule {
                            Button {
                                showingAddProduct = true
                            } label: {
                                Image(systemName: "plus")
                            }
                        }

                        Button {
                            showFilters.toggle()
                        } label: {
                            Image(systemName: showFilters ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle")
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Text("\(filteredProducts.count) \(lang.t("products_count"))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingAddProduct) {
            NavigationView {
                ProductEditView(product: $newProduct)
                    .navigationTitle(lang.t("add_product"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(lang.t("cancel")) {
                                showingAddProduct = false
                                newProduct = Product(name: "", category: "misc") // Reset
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(lang.t("save")) {
                                // TODO: Save new product to productStore
                                productStore.addProduct(newProduct)
                                showingAddProduct = false
                                newProduct = Product(name: "", category: "misc") // Reset
                            }
                        }
                    }
            }
        }
        .onAppear {
            // Load products for specific department
            productStore.loadProductsForDepartment(department)
        }
    }
}

struct ProductRowView: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text(product.localizedName)
                        .font(.headline)

                    // Category
                    Text(product.category.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Allergen badges
                HStack(spacing: 4) {
                    if product.glutenFree {
                        Text("🌾")
                            .font(.caption)
                    }
                    if product.lactoseFree {
                        Text("🥛")
                            .font(.caption)
                    }
                }
            }

            // Nutrition info
            if !product.nutritionInfo.isEmpty {
                Text(product.nutritionInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Allergens info
            if !product.allergensInfo.isEmpty {
                Text(product.allergensInfo)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // Price and unit
            HStack {
                if let price = product.basePrice, let currency = product.currency {
                    Text(String(format: "%.2f %@", price, currency))
                        .font(.subheadline)
                        .foregroundColor(.green)
                }

                if let unit = product.unit {
                    Text("за \(unit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProductDetailView: View {
    @EnvironmentObject var lang: LocalizationManager
    let product: Product

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(product.localizedName)
                        .font(.title)
                        .bold()

                    Text(product.category.capitalized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let price = product.basePrice, let currency = product.currency {
                        HStack {
                            Text(String(format: "%.2f %@", price, currency))
                                .font(.title2)
                                .foregroundColor(.green)

                            if let unit = product.unit {
                                Text("за \(unit)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Nutrition section
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.t("nutrition_per_100g"))
                        .font(.headline)

                    if let calories = product.calories {
                        NutritionRow(label: lang.t("calories_short"), value: "\(Int(calories)) \(lang.t("kcal"))")
                    }
                    if let protein = product.protein {
                        NutritionRow(label: lang.t("protein_short"), value: "\(protein) \(lang.t("grams"))")
                    }
                    if let fat = product.fat {
                        NutritionRow(label: lang.t("fat_short"), value: "\(fat) \(lang.t("grams"))")
                    }
                    if let carbs = product.carbs {
                        NutritionRow(label: lang.t("carbs_short"), value: "\(carbs) \(lang.t("grams"))")
                    }
                }
                .padding(.horizontal)

                // Allergens section
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.t("features"))
                        .font(.headline)

                    HStack(spacing: 16) {
                        AllergenBadge(
                            icon: "🌾",
                            label: lang.t("gluten_free_label"),
                            isActive: product.glutenFree
                        )

                        AllergenBadge(
                            icon: "🥛",
                            label: lang.t("lactose_free_label"),
                            isActive: product.lactoseFree
                        )
                    }
                }
                .padding(.horizontal)

                // Кнопка калькулятора ингредиентов
                NavigationLink {
                    TTIngredientCalculatorView(product: product)
                } label: {
                    Text(lang.t("ingredient_calculator"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.primary)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.vertical)
        }
        .navigationTitle(lang.t("product_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NutritionRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
        .padding(.vertical, 4)
    }
}

struct AllergenBadge: View {
    let icon: String
    let label: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
            Text(label)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
        .foregroundColor(isActive ? .green : .gray)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isActive ? Color.green.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}
