import Foundation

struct SystemProduct: Identifiable, Codable {

    let id: UUID
    let code: String

    let name: LocalizedName

    // КБЖУ на 100 г
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double

    let containsGluten: Bool
    let containsLactose: Bool

    let baseUnit: ProductUnit

    let techLosses: TechLossDefaults
}
