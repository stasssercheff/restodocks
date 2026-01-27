// Product.swift
import Foundation

struct Product: Identifiable, Codable {

    // MARK: - Base (уже используется)
    var id: UUID
    var name: String
    var price: Double

    // MARK: - Nutrition (на будущее, пока не используется)
    var calories: Double?
    var protein: Double?
    var fat: Double?
    var carbs: Double?

    // MARK: - Allergens
    var containsGluten: Bool?
    var containsLactose: Bool?

    // MARK: - Unit
    var unit: Unit?

    // MARK: - Init (совместим со старым кодом)
    init(
        id: UUID = UUID(),
        name: String,
        price: Double,
        calories: Double? = nil,
        protein: Double? = nil,
        fat: Double? = nil,
        carbs: Double? = nil,
        containsGluten: Bool? = nil,
        containsLactose: Bool? = nil,
        unit: Unit? = nil
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.containsGluten = containsGluten
        self.containsLactose = containsLactose
        self.unit = unit
    }
}
