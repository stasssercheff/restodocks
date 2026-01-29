//
//  ShiftCalculationType.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/10/26.
//


import Foundation

enum ShiftCalculationType: String, Codable, CaseIterable {
    case hourly      // почасовая
    case perShift    // посменная
    case fullDay     // полная смена (без времени)
}