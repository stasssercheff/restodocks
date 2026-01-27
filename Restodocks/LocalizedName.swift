//
//  LocalizedName.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/26/25.
//


import Foundation

struct LocalizedName: Codable {
    let ru: String
    let en: String
    let es: String
    let de: String
    let fr: String

    func value(for lang: String) -> String {
        switch lang {
        case "ru": return ru
        case "es": return es
        case "de": return de
        case "fr": return fr
        default: return en
        }
    }
}