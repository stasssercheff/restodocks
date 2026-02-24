//
//  Employee.swift
//  Restodocks
//

import Foundation

struct Employee: Codable, Identifiable, Hashable {
    let id: UUID
    let fullName: String
    let email: String
    var department: String
    var section: String?
    var roles: [String]
    let establishmentId: UUID
    var personalPin: String?
    var isActive: Bool
    var costPerUnit: Double?
    var payrollCountingMode: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
        case department
        case section
        case roles
        case establishmentId = "establishment_id"
        case personalPin = "personal_pin"
        case isActive = "is_active"
        case costPerUnit = "cost_per_unit"
        case payrollCountingMode = "payroll_counting_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var rolesArray: [String] { roles }
    var isOwner: Bool { roles.contains("owner") }
    var isChef: Bool { roles.contains("chef") }
    var isManager: Bool { roles.contains("manager") }
    var jobPosition: String? { roles.first { $0 != "owner" } }
    var isOwnerWithPosition: Bool { isOwner && jobPosition != nil }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Employee, rhs: Employee) -> Bool { lhs.id == rhs.id }
}
