// Product.swift
import Foundation

struct Product: Identifiable, Codable {

    // MARK: - Base
    var id: UUID
    var name: String
    var category: String

    // MARK: - Multi-language names
    var names: [String: String]? // ["ru": "Молоко", "en": "Milk", "es": "Leche", ...]

    // MARK: - Nutrition (КБЖУ)
    var calories: Double? // ккал
    var protein: Double? // граммы
    var fat: Double? // граммы
    var carbs: Double? // граммы

    // MARK: - Allergens
    var containsGluten: Bool?
    var containsLactose: Bool?

    // MARK: - Pricing
    var basePrice: Double? // базовая цена без учета валюты
    var currency: String? // код валюты (USD, EUR, RUB, etc.)

    // MARK: - Unit
    var unit: String? // кг, л, шт, etc.

    /// % отхода при зачистке (брутто → нетто). Источник: справочник по продукту/категории.
    var defaultWastePercent: Double?

    // MARK: - Suppliers (IDs связанных поставщиков)
    var supplierIds: [UUID]?

    // MARK: - Computed properties for display
    var localizedName: String {
        let lang = LocalizationManager.shared.currentLang
        if let localized = names?[lang] {
            return localized
        }
        return name // fallback to base name
    }

    var glutenFree: Bool {
        containsGluten == false
    }

    var lactoseFree: Bool {
        containsLactose == false
    }

    var nutritionInfo: String {
        var info = ""
        if let calories = calories {
            info += "\(LocalizationManager.shared.t("calories_abbr")): \(Int(calories)) "
        }
        if let protein = protein {
            info += "\(LocalizationManager.shared.t("protein_abbr")): \(protein)g "
        }
        if let fat = fat {
            info += "\(LocalizationManager.shared.t("fat_abbr")): \(fat)g "
        }
        if let carbs = carbs {
            info += "\(LocalizationManager.shared.t("carbs_abbr")): \(carbs)g "
        }
        return info.trimmingCharacters(in: .whitespaces)
    }

    var allergensInfo: String {
        var allergens: [String] = []
        if containsGluten == true {
            allergens.append(LocalizationManager.shared.t("gluten"))
        }
        if containsLactose == true {
            allergens.append(LocalizationManager.shared.t("lactose"))
        }
        return allergens.joined(separator: ", ")
    }

    var priceInfo: String {
        guard let price = basePrice, let currency = currency else { return "" }
        return "\(LocalizationManager.shared.t("price")): \(price) \(currency)"
    }

    // MARK: - Init
    init(
        id: UUID = UUID(),
        name: String,
        category: String,
        names: [String: String]? = nil,
        calories: Double? = nil,
        protein: Double? = nil,
        fat: Double? = nil,
        carbs: Double? = nil,
        containsGluten: Bool? = nil,
        containsLactose: Bool? = nil,
        basePrice: Double? = nil,
        currency: String? = nil,
        unit: String? = nil,
        defaultWastePercent: Double? = nil,
        supplierIds: [UUID]? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.names = names
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.containsGluten = containsGluten
        self.containsLactose = containsLactose
        self.basePrice = basePrice
        self.currency = currency
        self.unit = unit
        self.defaultWastePercent = defaultWastePercent
        self.supplierIds = supplierIds
    }
}
