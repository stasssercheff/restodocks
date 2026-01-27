//
//  ProductUnit.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/26/25.
//


import Foundation

enum ProductUnit: String, Codable, CaseIterable {
    case gram
    case kilogram
    case milliliter
    case liter
    case piece
}