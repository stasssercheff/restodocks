//
//  Department.swift
//  Restodocks
//

import Foundation

enum Department: String, Codable, CaseIterable, Identifiable {

    case kitchen
    case bar
    case hall
    case management

    // PRO
    case grill
    case pizza
    case sushi
    case bakery
    case pastry

    var id: String { rawValue }
}
