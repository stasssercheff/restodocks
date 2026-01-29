//
//  TTIngredient.swift
//  Restodocks
//
//  Ингредиент технологической карты: брутто → отход → нетто → ужарка → выход.
//  Процент отхода (брутто–нетто) и ужарки (статистический из процесса) считаются автоматически.
//

import Foundation

struct TTIngredient: Identifiable, Codable {
    var id: UUID
    var productId: UUID?
    var productName: String

    var cookingProcessId: UUID?
    var cookingProcessName: String?

    /// Брутто, г (до зачистки).
    var grossWeight: Double
    /// Нетто, г (после зачистки, до приготовления). Считается от брутто по % отхода или ввод вручную.
    var netWeight: Double
    var isNetWeightManual: Bool = false

    var finalCalories: Double
    var finalProtein: Double
    var finalFat: Double
    var finalCarbs: Double

    var cost: Double

    // MARK: - Автоматические показатели

    /// Процент отхода (брутто → нетто): (брутто - нетто) / брутто * 100.
    var wastePercentage: Double {
        guard grossWeight > 0 else { return 0 }
        return ((grossWeight - netWeight) / grossWeight) * 100.0
    }

    /// Процент ужарки (статистический, из процесса приготовления).
    func shrinkagePercentage(process: CookingProcess?) -> Double {
        process?.weightLossPercentage ?? 0
    }

    /// Выход, г: нетто * (1 - ужарка/100). Вес после приготовления.
    func yieldWeight(process: CookingProcess?) -> Double {
        let shrink = shrinkagePercentage(process: process)
        return netWeight * (1.0 - shrink / 100.0)
    }

    /// Цена за кг (из продукта).
    func pricePerKg(product: Product?) -> Double {
        product?.basePrice ?? 0
    }

    init(product: Product?, cookingProcess: CookingProcess?, grossWeight: Double, netWeight: Double? = nil, defaultCurrency: String) {
        self.id = UUID()
        self.productId = product?.id
        self.productName = product?.localizedName ?? ""

        self.grossWeight = grossWeight

        let waste = product?.defaultWastePercent ?? 0
        let computedNet = grossWeight * (1.0 - waste / 100.0)

        if let manual = netWeight {
            self.netWeight = manual
            self.isNetWeightManual = true
        } else {
            self.netWeight = computedNet
            self.isNetWeightManual = false
        }

        if let process = cookingProcess, let prod = product {
            self.cookingProcessId = process.id
            self.cookingProcessName = process.localizedName
            let processed = process.apply(to: prod, weight: self.netWeight)
            self.finalCalories = processed.totalCalories
            self.finalProtein = processed.totalProtein
            self.finalFat = processed.totalFat
            self.finalCarbs = processed.totalCarbs
        } else if let prod = product {
            self.cookingProcessId = nil
            self.cookingProcessName = nil
            self.finalCalories = ((prod.calories ?? 0) * self.netWeight) / 100.0
            self.finalProtein = ((prod.protein ?? 0) * y) / 100.0
            self.finalFat = ((prod.fat ?? 0) * y) / 100.0
            self.finalCarbs = ((prod.carbs ?? 0) * y) / 100.0
        } else {
            self.cookingProcessId = nil
            self.cookingProcessName = nil
            self.finalCalories = 0
            self.finalProtein = 0
            self.finalFat = 0
            self.finalCarbs = 0
        }

        if let basePrice = product?.basePrice {
            self.cost = (grossWeight / 1000.0) * basePrice
        } else {
            self.cost = 0.0
        }
    }

    mutating func updateGrossWeight(_ newGrossWeight: Double, product: Product?, cookingProcess: CookingProcess?) {
        grossWeight = newGrossWeight

        if !isNetWeightManual, let prod = product {
            let waste = prod.defaultWastePercent ?? 0
            netWeight = newGrossWeight * (1.0 - waste / 100.0)
        }

        recalcKBJUAndCost(product: product, cookingProcess: cookingProcess)
    }

    mutating func updateNetWeight(_ newNetWeight: Double, product: Product?, cookingProcess: CookingProcess?) {
        netWeight = newNetWeight
        isNetWeightManual = true
        recalcKBJUAndCost(product: product, cookingProcess: cookingProcess)
    }

    /// Для UI: процесс по текущему cookingProcessId.
    func process(from manager: CookingProcessManager) -> CookingProcess? {
        guard let id = cookingProcessId else { return nil }
        return manager.processById(id)
    }

    mutating func updateCookingProcess(_ newProcess: CookingProcess?, product: Product?) {
        cookingProcessId = newProcess?.id
        cookingProcessName = newProcess?.localizedName
        if !isNetWeightManual, let prod = product {
            let waste = prod.defaultWastePercent ?? 0
            netWeight = grossWeight * (1.0 - waste / 100.0)
        }
        recalcKBJUAndCost(product: product, cookingProcess: newProcess)
    }

    private mutating func recalcKBJUAndCost(product: Product?, cookingProcess: CookingProcess?) {
        if let process = cookingProcess, let prod = product {
            let processed = process.apply(to: prod, weight: netWeight)
            finalCalories = processed.totalCalories
            finalProtein = processed.totalProtein
            finalFat = processed.totalFat
            finalCarbs = processed.totalCarbs
        } else if let prod = product {
            finalCalories = ((prod.calories ?? 0) * netWeight) / 100.0
            finalProtein = ((prod.protein ?? 0) * netWeight) / 100.0
            finalFat = ((prod.fat ?? 0) * netWeight) / 100.0
            finalCarbs = ((prod.carbs ?? 0) * netWeight) / 100.0
        } else {
            finalCalories = 0
            finalProtein = 0
            finalFat = 0
            finalCarbs = 0
        }

        if let basePrice = product?.basePrice {
            cost = (grossWeight / 1000.0) * basePrice
        } else {
            cost = 0.0
        }
    }

    var nutritionSummary: String {
        String(format: "%.1f ккал, Б:%.1f Ж:%.1f У:%.1f",
               finalCalories, finalProtein, finalFat, finalCarbs)
    }

    var grossWeightInfo: String { String(format: "%.1f г", grossWeight) }
    var netWeightInfo: String { String(format: "%.1f г", netWeight) }
    var costInfo: String { String(format: "%.2f ₽", cost) }

    /// Ужарка ранее считалась от брутто–нетто; теперь используем shrinkagePercentage(process:).
    var weightLossPercentage: Double {
        guard grossWeight > 0 else { return 0 }
        return ((grossWeight - netWeight) / grossWeight) * 100.0
    }
}
