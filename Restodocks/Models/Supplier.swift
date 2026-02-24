//
//  Supplier.swift
//  Restodocks
//

import Foundation

struct Supplier: Codable, Identifiable {
    let id: UUID
    let establishmentId: UUID
    var name: String
    var phone: String?
    var email: String?
    var address: String?
    var comment: String?

    enum CodingKeys: String, CodingKey {
        case id
        case establishmentId = "establishment_id"
        case name
        case phone
        case email
        case address
        case comment
    }

    init(id: UUID, establishmentId: UUID, name: String, phone: String? = nil, email: String? = nil, address: String? = nil, comment: String? = nil) {
        self.id = id
        self.establishmentId = establishmentId
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
        self.comment = comment
    }
}
