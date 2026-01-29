//
//  CookingProcess.swift
//  Restodocks
//
//  Кулинарные процессы и их влияние на КБЖУ продуктов
//

import Foundation

struct CookingProcess: Identifiable, Codable {
    let id: UUID
    let name: String
    let localizedNames: [String: String]

    // Коэффициенты изменения питательной ценности
    let calorieMultiplier: Double      // Множитель калорий
    let proteinMultiplier: Double      // Множитель белка
    let fatMultiplier: Double          // Множитель жиров
    let carbsMultiplier: Double        // Множитель углеводов

    // Изменение веса (потери при приготовлении)
    let weightLossPercentage: Double   // Процент потери веса

    // Категории продуктов, к которым применим процесс
    let applicableCategories: [String]

    var localizedName: String {
        let lang = LocalizationManager.shared.currentLang
        return localizedNames[lang] ?? name
    }

    // Применить процесс к продукту
    func apply(to product: Product, weight: Double) -> ProcessedProduct {
        let finalWeight = weight * (1.0 - weightLossPercentage / 100.0)

        let processedCalories = (product.calories ?? 0) * calorieMultiplier
        let processedProtein = (product.protein ?? 0) * proteinMultiplier
        let processedFat = (product.fat ?? 0) * fatMultiplier
        let processedCarbs = (product.carbs ?? 0) * carbsMultiplier

        return ProcessedProduct(
            originalProduct: product,
            cookingProcess: self,
            originalWeight: weight,
            finalWeight: finalWeight,
            processedCalories: processedCalories,
            processedProtein: processedProtein,
            processedFat: processedFat,
            processedCarbs: processedCarbs
        )
    }
}

// Обработанный продукт с учетом кулинарного процесса
struct ProcessedProduct {
    let originalProduct: Product
    let cookingProcess: CookingProcess
    let originalWeight: Double
    let finalWeight: Double
    let processedCalories: Double
    let processedProtein: Double
    let processedFat: Double
    let processedCarbs: Double

    var totalCalories: Double {
        (processedCalories * finalWeight) / 100.0
    }

    var totalProtein: Double {
        (processedProtein * finalWeight) / 100.0
    }

    var totalFat: Double {
        (processedFat * finalWeight) / 100.0
    }

    var totalCarbs: Double {
        (processedCarbs * finalWeight) / 100.0
    }
}

// Менеджер кулинарных процессов
class CookingProcessManager {
    static let shared = CookingProcessManager()

    let processes: [CookingProcess] = [
        // Варка
        CookingProcess(
            id: UUID(),
            name: "boiling",
            localizedNames: [
                "ru": "Варка",
                "en": "Boiling",
                "es": "Hervido",
                "de": "Kochen",
                "fr": "Ébullition"
            ],
            calorieMultiplier: 0.9,
            proteinMultiplier: 0.95,
            fatMultiplier: 1.0,
            carbsMultiplier: 1.0,
            weightLossPercentage: 25.0,
            applicableCategories: ["meat", "vegetables", "grains", "seafood"]
        ),

        // Жарка на масле
        CookingProcess(
            id: UUID(),
            name: "frying_oil",
            localizedNames: [
                "ru": "Жарка на масле",
                "en": "Frying in Oil",
                "es": "Fritura en aceite",
                "de": "Braten in Öl",
                "fr": "Friture à l'huile"
            ],
            calorieMultiplier: 1.2,
            proteinMultiplier: 0.9,
            fatMultiplier: 1.3,
            carbsMultiplier: 1.0,
            weightLossPercentage: 15.0,
            applicableCategories: ["meat", "vegetables", "seafood"]
        ),

        // Жарка на гриле
        CookingProcess(
            id: UUID(),
            name: "grilling",
            localizedNames: [
                "ru": "Жарка на гриле",
                "en": "Grilling",
                "es": "Asado a la parrilla",
                "de": "Grillen",
                "fr": "Grillade"
            ],
            calorieMultiplier: 0.95,
            proteinMultiplier: 0.9,
            fatMultiplier: 0.8,
            carbsMultiplier: 1.0,
            weightLossPercentage: 20.0,
            applicableCategories: ["meat", "vegetables", "seafood"]
        ),

        // Запекание
        CookingProcess(
            id: UUID(),
            name: "baking",
            localizedNames: [
                "ru": "Запекание",
                "en": "Baking",
                "es": "Horneado",
                "de": "Backen",
                "fr": "Cuisson au four"
            ],
            calorieMultiplier: 0.95,
            proteinMultiplier: 0.9,
            fatMultiplier: 0.9,
            carbsMultiplier: 1.0,
            weightLossPercentage: 15.0,
            applicableCategories: ["meat", "vegetables", "seafood"]
        ),

        // Тушение
        CookingProcess(
            id: UUID(),
            name: "stewing",
            localizedNames: [
                "ru": "Тушение",
                "en": "Stewing",
                "es": "Estofado",
                "de": "Schmoren",
                "fr": "Étuve"
            ],
            calorieMultiplier: 0.9,
            proteinMultiplier: 0.95,
            fatMultiplier: 0.95,
            carbsMultiplier: 1.0,
            weightLossPercentage: 30.0,
            applicableCategories: ["meat", "vegetables"]
        ),

        // Пассерование (быстрое обжаривание)
        CookingProcess(
            id: UUID(),
            name: "sauteing",
            localizedNames: [
                "ru": "Пассерование",
                "en": "Sautéing",
                "es": "Salteado",
                "de": "Anbraten",
                "fr": "Sautage"
            ],
            calorieMultiplier: 1.1,
            proteinMultiplier: 0.9,
            fatMultiplier: 1.2,
            carbsMultiplier: 1.0,
            weightLossPercentage: 10.0,
            applicableCategories: ["vegetables", "meat"]
        ),

        // Су-вид
        CookingProcess(
            id: UUID(),
            name: "sous_vide",
            localizedNames: [
                "ru": "Су-вид",
                "en": "Sous-vide",
                "es": "Sous-vide",
                "de": "Sous-vide",
                "fr": "Sous-vide"
            ],
            calorieMultiplier: 0.98,
            proteinMultiplier: 0.95,
            fatMultiplier: 0.95,
            carbsMultiplier: 1.0,
            weightLossPercentage: 5.0,
            applicableCategories: ["meat", "seafood", "vegetables"]
        ),

        // Ферментация
        CookingProcess(
            id: UUID(),
            name: "fermentation",
            localizedNames: [
                "ru": "Ферментация",
                "en": "Fermentation",
                "es": "Fermentación",
                "de": "Fermentation",
                "fr": "Fermentation"
            ],
            calorieMultiplier: 0.9,
            proteinMultiplier: 1.0,
            fatMultiplier: 0.95,
            carbsMultiplier: 0.8,
            weightLossPercentage: 10.0,
            applicableCategories: ["dairy", "vegetables"]
        ),

        // Обжиг горелкой
        CookingProcess(
            id: UUID(),
            name: "torch_browning",
            localizedNames: [
                "ru": "Обжиг горелкой",
                "en": "Torch Browning",
                "es": "Dorado con soplete",
                "de": "Flamme bräunen",
                "fr": "Brûlage au chalumeau"
            ],
            calorieMultiplier: 1.05,
            proteinMultiplier: 0.95,
            fatMultiplier: 1.0,
            carbsMultiplier: 1.0,
            weightLossPercentage: 2.0,
            applicableCategories: ["meat", "seafood", "dairy"]
        ),

        // Бланширование
        CookingProcess(
            id: UUID(),
            name: "blanching",
            localizedNames: [
                "ru": "Бланширование",
                "en": "Blanching",
                "es": "Blanqueado",
                "de": "Blanchieren",
                "fr": "Blanchiment"
            ],
            calorieMultiplier: 0.95,
            proteinMultiplier: 0.98,
            fatMultiplier: 1.0,
            carbsMultiplier: 1.0,
            weightLossPercentage: 15.0,
            applicableCategories: ["vegetables"]
        ),

        // Пароварка
        CookingProcess(
            id: UUID(),
            name: "steaming",
            localizedNames: [
                "ru": "Пароварка",
                "en": "Steaming",
                "es": "Cocción al vapor",
                "de": "Dämpfen",
                "fr": "Cuisson à la vapeur"
            ],
            calorieMultiplier: 0.95,
            proteinMultiplier: 0.95,
            fatMultiplier: 0.9,
            carbsMultiplier: 1.0,
            weightLossPercentage: 10.0,
            applicableCategories: ["vegetables", "seafood", "meat"]
        ),

        // Сырое состояние (без обработки)
        CookingProcess(
            id: UUID(),
            name: "raw",
            localizedNames: [
                "ru": "Сырое",
                "en": "Raw",
                "es": "Crudo",
                "de": "Roh",
                "fr": "Cru"
            ],
            calorieMultiplier: 1.0,
            proteinMultiplier: 1.0,
            fatMultiplier: 1.0,
            carbsMultiplier: 1.0,
            weightLossPercentage: 0.0,
            applicableCategories: ["all"]
        )
    ]

    // Получить процессы, применимые к категории продукта
    func processesForCategory(_ category: String) -> [CookingProcess] {
        return processes.filter { process in
            process.applicableCategories.contains(category) || process.applicableCategories.contains("all")
        }
    }

    // Найти процесс по ID
    func processById(_ id: UUID) -> CookingProcess? {
        return processes.first { $0.id == id }
    }
}