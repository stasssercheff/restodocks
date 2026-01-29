import Foundation

enum Department: String, CaseIterable, Identifiable, Codable {
    case kitchen
    case bar
    case hall
    case management

    var id: String { rawValue }
}
