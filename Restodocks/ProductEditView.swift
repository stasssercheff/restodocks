// ProductEditView.swift
import SwiftUI

struct ProductEditView: View {
    @Binding var product: Product
    @ObservedObject var lang = LocalizationManager.shared
    @EnvironmentObject var appState: AppState

    let categories = [
        ("vegetables", "Овощи"),
        ("fruits", "Фрукты"),
        ("meat", "Мясо"),
        ("fish", "Рыба"),
        ("dairy", "Молочные продукты"),
        ("grains", "Злаки"),
        ("spices", "Специи"),
        ("misc", "Разное")
    ]

    var body: some View {
        Form {
            Section(header: Text(lang.t("product_details"))) {
                TextField(lang.t("product_name"), text: $product.name)

                Picker(lang.t("category"), selection: $product.category) {
                    ForEach(categories, id: \.0) { cat in
                        Text(cat.1).tag(cat.0)
                    }
                }

                Picker(lang.t("unit"), selection: Binding(
                    get: { product.unit ?? "кг" },
                    set: { product.unit = $0 }
                )) {
                    Text("кг").tag("кг")
                    Text("г").tag("г")
                    Text("л").tag("л")
                    Text("мл").tag("мл")
                    Text("шт").tag("шт")
                }

                HStack {
                    Text(lang.t("price"))
                    Spacer()
                    TextField("0.00", value: $product.basePrice, formatter: NumberFormatter.currency)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                Picker(lang.t("currency"), selection: Binding(
                    get: { product.currency ?? appState.defaultCurrency },
                    set: { product.currency = $0 }
                )) {
                    Text("RUB").tag("RUB")
                    Text("USD").tag("USD")
                    Text("EUR").tag("EUR")
                }
            }

            Section(header: Text(lang.t("nutrition"))) {
                HStack {
                    Text(lang.t("calories"))
                    Spacer()
                    TextField("0", value: $product.calories, formatter: NumberFormatter.integer)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("ккал")
                }

                HStack {
                    Text(lang.t("protein_abbr"))
                    Spacer()
                    TextField("0.0", value: $product.protein, formatter: NumberFormatter.decimal)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("г")
                }

                HStack {
                    Text(lang.t("fat_abbr"))
                    Spacer()
                    TextField("0.0", value: $product.fat, formatter: NumberFormatter.decimal)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("г")
                }

                HStack {
                    Text(lang.t("carbs_abbr"))
                    Spacer()
                    TextField("0.0", value: $product.carbs, formatter: NumberFormatter.decimal)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("г")
                }
            }

            Section(header: Text(lang.t("allergens"))) {
                Toggle(lang.t("contains_gluten"), isOn: Binding(
                    get: { product.containsGluten ?? false },
                    set: { product.containsGluten = $0 }
                ))

                Toggle(lang.t("contains_lactose"), isOn: Binding(
                    get: { product.containsLactose ?? false },
                    set: { product.containsLactose = $0 }
                ))
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

    static var decimal: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }

    static var integer: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        return f
    }
}
