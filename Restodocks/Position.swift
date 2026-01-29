//
//  Position.swift
//  Restodocks
//

import Foundation

enum Position: String, Codable, CaseIterable, Identifiable {

    // ===== УПРАВЛЕНИЕ КУХНЕЙ =====
    case sousChef
    case brigadeLeader

    // ===== ГЦ / ХЦ =====
    case linecook          // повар
    case seniorCook        // старший повар
    case serviceCook       // повар раздачи

    // ===== ЗАГОТОВОЧНЫЙ ЦЕХ =====
    case prepCook
    case seniorPrepCook

    // ===== ГРИЛЬ =====
    case grillCook
    case seniorGrillCook

    // ===== СУШИ =====
    case sushiChef
    case seniorSushiChef

    // ===== ПИЦЦА =====
    case pizzaiolo
    case seniorPizzaiolo

    // ===== КОНДИТЕРСКИЙ ЦЕХ =====
    case pastryChef
    case seniorPastryChef

    // ===== КЛИНИНГ =====
    case dishwasher        // сотрудник мойки

    // ===== БАР =====
    case barManager
    case seniorBartender
    case bartender
    case barista

    // ===== ЗАЛ =====
    case hallManager
    case cashier
    case waiter
    case runner
    case cleaner

    // ===== МЕНЕДЖМЕНТ =====
    case headChef
    case director
    case owner
    case generalManager

    var id: String { rawValue }

    // ===== ДЕПАРТАМЕНТ =====
    var department: Department {
        switch self {

        case .sousChef,
             .brigadeLeader,
             .linecook,
             .seniorCook,
             .serviceCook,
             .prepCook,
             .seniorPrepCook,
             .grillCook,
             .seniorGrillCook,
             .sushiChef,
             .seniorSushiChef,
             .pizzaiolo,
             .seniorPizzaiolo,
             .pastryChef,
             .seniorPastryChef,
             .dishwasher:
            return .kitchen

        case .barManager,
             .seniorBartender,
             .bartender,
             .barista:
            return .bar

        case .hallManager,
             .cashier,
             .waiter,
             .runner,
             .cleaner:
            return .hall

        case .headChef,
             .director,
             .owner,
             .generalManager:
            return .management
        }
    }

    // ===== ЦЕХ =====
    var kitchenSection: KitchenSection? {
        switch self {

        // управление кухней
        case .sousChef,
             .brigadeLeader:
            return .kitchenManagement

        // ГЦ / ХЦ
        // ⚠️ определяется выбранным цехом (hot / cold)
        case .linecook,
             .seniorCook,
             .serviceCook:
            return nil

        // заготовочный
        case .prepCook,
             .seniorPrepCook:
            return .prep

        // гриль
        case .grillCook,
             .seniorGrillCook:
            return .grill

        // суши
        case .sushiChef,
             .seniorSushiChef:
            return .sushiBar

        // пицца
        case .pizzaiolo,
             .seniorPizzaiolo:
            return .pizza

        // кондитерка
        case .pastryChef,
             .seniorPastryChef:
            return .pastry

        // клининг
        case .dishwasher:
            return .cleaning

        default:
            return nil
        }
    }
}
