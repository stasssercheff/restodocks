//
//  ShiftType.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/10/26.
//


import Foundation

enum ShiftType: String, Codable {
    case fixedTime      // есть начало и конец
    case fullDay        // с открытия до закрытия
}