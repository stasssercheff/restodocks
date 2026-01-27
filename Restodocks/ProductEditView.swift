// ProductEditView.swift
import SwiftUI

struct ProductEditView: View {
    @Binding var product: Product
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        Form {
            Section(header: Text(lang.t("product_details"))) {
                TextField(lang.t("product_name"), text: $product.name)
                HStack {
                    Text(lang.t("price"))
                    Spacer()
                    TextField("0.00", value: $product.price, formatter: NumberFormatter.currency)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .navigationTitle(lang.t("edit_product"))
    }
}

// небольшой вспомогательный NumberFormatter
fileprivate extension NumberFormatter {
    static var currency: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }
}
