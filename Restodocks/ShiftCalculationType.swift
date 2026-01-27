import Foundation

enum ShiftCalculationType: String, Codable, CaseIterable {
    case hourly      // почасовая
    case perShift    // посменная
    case fullDay     // полная смена (без времени)
}