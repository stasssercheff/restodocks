//
//  KitchenSection.swift
//  Restodocks
//

import Foundation

enum KitchenSection: String, Codable, CaseIterable, Identifiable {

    // ===== ОСНОВНЫЕ ЦЕХА =====
    case hotKitchen          // горячий цех
    case coldKitchen         // холодный цех
    case prep                // заготовочный
    case pastry              // кондитерский цех

    // ===== PRO =====
    case grill               // гриль (pro)
    case pizza               // пицца (pro)
    case sushiBar            // сушибар (pro)
    case bakery              // выпечка (pro)

    // ===== УПРАВЛЕНИЕ =====
    case kitchenManagement   // управление кухней

    // ===== КЛИНИНГ =====
    case cleaning             // мойка / клининг

    var id: String { rawValue }
}
