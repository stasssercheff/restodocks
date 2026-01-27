//
//  TechLossDefaults.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/26/25.
//


import Foundation

struct TechLossDefaults: Codable {

    /// % отхода при зачистке
    let trimLoss: Double

    /// % ужарки / уварки
    let cookingLoss: Double

    /// % потерь при запекании
    let bakingLoss: Double

    /// % потерь при sous-vide
    let sousVideLoss: Double
}