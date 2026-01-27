import SwiftUI

struct KitchenMenuView: View {
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        Text(lang.t("menu"))
            .font(.largeTitle)
            .navigationTitle(lang.t("menu"))
    }
}