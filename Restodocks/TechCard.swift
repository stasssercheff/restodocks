//
//  TechCard.swift
//  Restodocks
//
//  Технологическая карта (ТТК)
//

import Foundation

enum TechCardType: String, Codable, CaseIterable {
    case dish           // Карточка блюда: пересчёт по порциям
    case semiFinished   // Полуфабрикат: любое значение ключевое, пропорциональный пересчёт
}

struct TechCard: Identifiable, Codable {
    let id: UUID
    var dishName: String
    var dishNameLocalized: [String: String]
    var category: String
    var portionWeight: Double
    var yield: Double
    var ingredients: [TTIngredient]
    var technology: String
    /// Переводы технологии приготовления по языкам (ru, en, es, de, fr). Источник — technology.
    var technologyLocalized: [String: String]
    /// Для полуфабриката: комментарий (напр. «Разлить по вакуумным пакетам»).
    var comment: String
    /// Блюдо (пересчёт по порциям) или полуфабрикат (пропорциональный пересчёт).
    var cardType: TechCardType
    /// Для блюда: рецепт рассчитан на basePortions порций. Пересчёт = (qty / basePortions) * выбранные порции.
    var basePortions: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        dishName: String,
        dishNameLocalized: [String: String] = [:],
        category: String = "main",
        portionWeight: Double = 0,
        yield: Double = 0,
        ingredients: [TTIngredient] = [],
        technology: String = "",
        technologyLocalized: [String: String] = [:],
        comment: String = "",
        cardType: TechCardType = .dish,
        basePortions: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.dishName = dishName
        self.dishNameLocalized = dishNameLocalized
        self.category = category
        self.portionWeight = portionWeight
        self.yield = yield
        self.ingredients = ingredients
        self.technology = technology
        self.technologyLocalized = technologyLocalized
        self.comment = comment
        self.cardType = cardType
        self.basePortions = max(1, basePortions)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        dishName = try c.decode(String.self, forKey: .dishName)
        dishNameLocalized = try c.decodeIfPresent([String: String].self, forKey: .dishNameLocalized) ?? [:]
        category = try c.decode(String.self, forKey: .category)
        portionWeight = try c.decode(Double.self, forKey: .portionWeight)
        yield = try c.decode(Double.self, forKey: .yield)
        ingredients = try c.decode([TTIngredient].self, forKey: .ingredients)
        technology = try c.decode(String.self, forKey: .technology)
        technologyLocalized = try c.decodeIfPresent([String: String].self, forKey: .technologyLocalized) ?? [:]
        comment = try c.decode(String.self, forKey: .comment)
        cardType = try c.decode(TechCardType.self, forKey: .cardType)
        basePortions = try c.decode(Int.self, forKey: .basePortions)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(dishName, forKey: .dishName)
        try c.encode(dishNameLocalized, forKey: .dishNameLocalized)
        try c.encode(category, forKey: .category)
        try c.encode(portionWeight, forKey: .portionWeight)
        try c.encode(yield, forKey: .yield)
        try c.encode(ingredients, forKey: .ingredients)
        try c.encode(technology, forKey: .technology)
        try c.encode(technologyLocalized, forKey: .technologyLocalized)
        try c.encode(comment, forKey: .comment)
        try c.encode(cardType, forKey: .cardType)
        try c.encode(basePortions, forKey: .basePortions)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    // Итоговые питательные вещества блюда
    var totalCalories: Double {
        ingredients.reduce(0) { $0 + $1.finalCalories }
    }

    var totalProtein: Double {
        ingredients.reduce(0) { $0 + $1.finalProtein }
    }

    var totalFat: Double {
        ingredients.reduce(0) { $0 + $1.finalFat }
    }

    var totalCarbs: Double {
        ingredients.reduce(0) { $0 + $1.finalCarbs }
    }

    // Итоговая стоимость блюда
    var totalCost: Double {
        ingredients.reduce(0) { $0 + $1.cost }
    }

    // Итоговый вес всех ингредиентов (нетто)
    var totalWeight: Double {
        ingredients.reduce(0) { $0 + $1.netWeight }
    }

    // Итоговый вес брутто
    var totalGrossWeight: Double {
        ingredients.reduce(0) { $0 + $1.grossWeight }
    }

    /// Суммарный выход блюда (сумма выходов ингредиентов после ужарки).
    func totalYield(manager: CookingProcessManager) -> Double {
        ingredients.reduce(0) { acc, ing in
            acc + ing.yieldWeight(process: ing.process(from: manager))
        }
    }

    var localizedDishName: String {
        let lang = LocalizationManager.shared.currentLang
        return dishNameLocalized[lang] ?? dishName
    }

    /// Технология приготовления для текущего (или заданного) языка: перевод или исходный текст.
    func localizedTechnology(for lang: String? = nil) -> String {
        let l = lang ?? LocalizationManager.shared.currentLang
        if let s = technologyLocalized[l], !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        return technology
    }
}