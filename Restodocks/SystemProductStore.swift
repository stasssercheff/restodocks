//
//  SystemProductStore.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/26/25.
//


import Foundation

final class SystemProductStore {

    static let shared = SystemProductStore()

    private(set) var products: [SystemProduct] = []

    private init() {
        load()
    }

    private func load() {
        guard
            let url = Bundle.main.url(forResource: "system_products", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            print("❌ system_products.json not found")
            return
        }

        do {
            products = try JSONDecoder().decode([SystemProduct].self, from: data)
            print("✅ Loaded \(products.count) system products")
        } catch {
            print("❌ JSON decode error:", error)
        }
    }

    func product(by id: UUID) -> SystemProduct? {
        products.first { $0.id == id }
    }
}