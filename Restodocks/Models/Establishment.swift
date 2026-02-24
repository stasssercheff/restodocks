//
//  Establishment.swift
//  Restodocks
//

import Foundation

struct Establishment: Codable, Identifiable {
    let id: UUID
    let name: String
    let pinCode: String
    var ownerId: UUID?
    var address: String?
    var phone: String?
    var email: String?
    var defaultCurrency: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case pinCode = "pin_code"
        case ownerId = "owner_id"
        case address
        case phone
        case email
        case defaultCurrency = "default_currency"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
