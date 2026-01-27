//
//  EmployeeEntity+Roles.swift
//  Restodocks
//

import Foundation

extension EmployeeEntity {

    var rolesArray: [String] {
        get {
            roles as? [String] ?? []
        }
        set {
            roles = newValue as NSObject
        }
    }

    // MARK: - Helpers

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