//
//  DemoTechCards.swift
//  Restodocks
//
//  Демо-карточки ТТК для экранов поваров (список цехов).
//

import Foundation

enum DemoTechCards {
    static func cards(defaultCurrency: String = "RUB") -> [TechCard] {
        [
            dishCard(currency: defaultCurrency),
            semiFinishedCard(currency: defaultCurrency),
        ]
    }

    private static func dishCard(currency: String) -> TechCard {
        var ing1 = TTIngredient(product: nil, cookingProcess: nil, grossWeight: 1, netWeight: nil, defaultCurrency: currency)
        ing1.productName = "ПФ Пашот"
        var ing2 = TTIngredient(product: nil, cookingProcess: nil, grossWeight: 40, netWeight: nil, defaultCurrency: currency)
        ing2.productName = "ПФ Соус Тартар"
        var ing3 = TTIngredient(product: nil, cookingProcess: nil, grossWeight: 70, netWeight: nil, defaultCurrency: currency)
        ing3.productName = "Деревенский хлеб"
        return TechCard(
            dishName: "Яйца Бенедикт",
            dishNameLocalized: ["ru": "Яйца Бенедикт", "en": "Eggs Benedict"],
            category: "main",
            portionWeight: 0,
            yield: 0,
            ingredients: [ing1, ing2, ing3],
            technology: "Приготовить пашот. Подсушить хлеб в духовке 3–4 мин. Собрать: хлеб, шпинат, яйцо пашот, соус голландский, микрозелень.",
            comment: "",
            cardType: .dish,
            basePortions: 1
        )
    }

    private static func semiFinishedCard(currency: String) -> TechCard {
        var ing1 = TTIngredient(product: nil, cookingProcess: nil, grossWeight: 1250, netWeight: nil, defaultCurrency: currency)
        ing1.productName = "Перец болгарский"
        var ing2 = TTIngredient(product: nil, cookingProcess: nil, grossWeight: 415, netWeight: nil, defaultCurrency: currency)
        ing2.productName = "Помидор"
        var ing3 = TTIngredient(product: nil, cookingProcess: nil, grossWeight: 480, netWeight: nil, defaultCurrency: currency)
        ing3.productName = "Лук красный"
        var ing4 = TTIngredient(product: nil, cookingProcess: nil, grossWeight: 60, netWeight: nil, defaultCurrency: currency)
        ing4.productName = "Чесночное масло ПФ"
        return TechCard(
            dishName: "Соус из печеного перца",
            dishNameLocalized: ["ru": "Соус из печеного перца", "en": "Baked Bell Pepper Sauce"],
            category: "main",
            portionWeight: 0,
            yield: 1600,
            ingredients: [ing1, ing2, ing3, ing4],
            technology: "Очистить перец, нарезать. Смешать с томатами и луком, чесночным маслом, солью, перцем. Запекать 60–80 мин при 180 °C, макс. конвекция. Пюрировать.",
            comment: "После завершения разлить по вакуумным пакетам.",
            cardType: .semiFinished,
            basePortions: 1
        )
    }
}
