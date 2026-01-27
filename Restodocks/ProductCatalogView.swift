// ProductCatalogView.swift
import SwiftUI

struct ProductCatalogView: View {

    @ObservedObject var lang = LocalizationManager.shared

    @State private var products: [Product] = [
        Product(id: UUID(), name: "Tomato",  price: 2.5),
        Product(id: UUID(), name: "Cheese",  price: 5.0),
        Product(id: UUID(), name: "Chicken", price: 4.2)
    ]

    var body: some View {
        List {
            ForEach($products) { $product in
                NavigationLink {
                    ProductEditView(product: $product)
                } label: {
                    VStack(alignment: .leading) {
                        Text(product.name)
                            .font(.headline)
                        Text("\(product.price, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(lang.t("products"))
    }
}
