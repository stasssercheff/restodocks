//
//  ProductStore.swift
//  Restodocks
//
//  Номенклатура заведения = стартовая база (1000 продуктов) + свои продукты.
//  Источник для ТТК и инвентаризации.
//

import Foundation
import Combine

class ProductStore: ObservableObject {
    static let shared = ProductStore()

    /// Номенклатура: стартовая база + кастомные продукты. Источник для ТТК и инвентаризации.
    @Published var allProducts: [Product] = []
    @Published var categories: [String] = []
    @Published var isLoading = false
    @Published var error: Error?

    /// Стартовая база (1000 продуктов, КБЖУ, лактоза, глютен). Read-only.
    private(set) var starterProducts: [Product] = []
    /// Свои продукты заведения. Можно дополнять.
    private(set) var customProducts: [Product] = []

    private init() {
        loadNomenclature()
    }

    /// Загрузить номенклатуру: стартовая база + свои.
    func loadNomenclature() {
        loadStarterCatalog()
    }

    /// Загрузить стартовую базу из starter_catalog.json.
    private func loadStarterCatalog() {
        isLoading = true
        error = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let url = Bundle.main.url(forResource: "starter_catalog", withExtension: "json") else {
                    throw NSError(domain: "ProductStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "starter_catalog.json not found"])
                }
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([Product].self, from: data)

                DispatchQueue.main.async {
                    self?.starterProducts = decoded
                    self?.recomputeNomenclature()
                    self?.isLoading = false
                    print("✅ Стартовая база: \(decoded.count) продуктов. Номенклатура: \(self?.allProducts.count ?? 0)")
                }
            } catch {
                DispatchQueue.main.async {
                    self?.error = error
                    self?.isLoading = false
                    self?.starterProducts = []
                    self?.allProducts = []
                    self?.categories = []
                    print("❌ Ошибка загрузки starter_catalog: \(error)")
                }
            }
        }
    }

    private func recomputeNomenclature() {
        allProducts = starterProducts + customProducts
        categories = Array(Set(allProducts.map { $0.category })).sorted()
    }

    /// Добавить свой продукт в номенклатуру.
    func addProduct(_ product: Product) {
        customProducts.append(product)
        recomputeNomenclature()
    }

    /// Удалить свой продукт из номенклатуры (только кастомные).
    func removeCustomProduct(id: UUID) {
        customProducts.removeAll { $0.id == id }
        recomputeNomenclature()
    }

    func products(inCategory category: String? = nil,
                  filteredByGluten glutenFree: Bool? = nil,
                  lactoseFree: Bool? = nil,
                  searchText: String = "") -> [Product] {

        return allProducts.filter { product in
            if let category = category, product.category != category { return false }
            if let glutenFree = glutenFree, product.glutenFree != glutenFree { return false }
            if let lactoseFree = lactoseFree, product.lactoseFree != lactoseFree { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                if product.localizedName.lowercased().contains(q) { return true }
                if product.name.lowercased().contains(q) { return true }
                for (_, v) in product.names ?? [:] {
                    if v.lowercased().contains(q) { return true }
                }
                return false
            }
            return true
        }
    }

    func productsInCategory(_ category: String) -> [Product] {
        allProducts.filter { $0.category == category }
    }

    func searchProducts(_ searchText: String) -> [Product] {
        products(searchText: searchText)
    }

    /// Для совместимости: «отдел» не используется, номенклатура общая.
    func loadProductsForDepartment(_ department: String) {
        loadNomenclature()
    }

    func loadProducts() {
        loadNomenclature()
    }
}
