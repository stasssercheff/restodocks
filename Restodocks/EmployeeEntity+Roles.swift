//
//  EmployeeEntity+Roles.swift
//  Restodocks
//

import Foundation

extension EmployeeEntity {

    // Transformable -> [String]
    var rolesArray: [String] {
        get {
            roles as? [String] ?? []
        }
        set {
            roles = newValue as NSObject
        }
    }

    // MARK: - Role helpers (READ ONLY)

    var isOwner: Bool {
        rolesArray.contains("owner")
    }

    var isChef: Bool {
        rolesArray.contains("chef")
    }

    var isManager: Bool {
        rolesArray.contains("manager")
    }

    /// Должность (роль) для работы — первая не-owner роль. Собственник — не должность.
    var jobPosition: String? {
        rolesArray.first { $0 != "owner" }
    }

    /// Собственник с выбранной должностью (шеф, менеджер и т.д.)
    var isOwnerWithPosition: Bool {
        isOwner && jobPosition != nil
    }
}
