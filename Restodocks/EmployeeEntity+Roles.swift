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
}
