//
//  HotKitchenTTKView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/6/26.
//

import SwiftUI

struct HotKitchenTTKView: View {
    @EnvironmentObject var lang: LocalizationManager

    private var demoCards: [TechCard] {
        DemoTechCards.cards(defaultCurrency: "RUB")
    }

    var body: some View {
        List {
            Section {
                Text(lang.t("hot_kitchen_ttk"))
                    .foregroundColor(.secondary)
            }
            Section(header: Text(lang.t("tech_cards"))) {
                ForEach(demoCards) { card in
                    NavigationLink(value: card.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.localizedDishName)
                                    .font(.headline)
                                Text(card.cardType == .dish ? lang.t("card_type_dish") : lang.t("card_type_semi_finished"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationDestination(for: UUID.self) { cardId in
            if let card = demoCards.first(where: { $0.id == cardId }) {
                TTKCardView(card: card)
            }
        }
        .navigationTitle(lang.t("ttk"))
    }
}
