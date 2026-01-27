//
//  Position.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/20/25.
//


import Foundation

enum Position: String, CaseIterable, Identifiable {

    // 👑 Владельцы / управление
    case owner
    case director
    case manager
    case chef

    // 🍳 Кухня
    case sousChef
    case seniorCook
    case cook
    case prepCook
    case dishwasher

    // 🍸 Бар
    case bartender
    case barista

    // 🛎 Зал
    case waiter
    case cashier
    case runner
    case hallManager

    var id: String { rawValue }
}