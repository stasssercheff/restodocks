//
//  EmployeeRole.swift
//  Restodocks
//

import Foundation

enum EmployeeRole: String, Codable, CaseIterable, Identifiable {

    case owner
    case manager
    case chef
    case waiter
    case cashier

    var id: String { rawValue }
}
