import Foundation

enum ShiftType: String, Codable {
    case fixedTime      // есть начало и конец
    case fullDay        // с открытия до закрытия
}