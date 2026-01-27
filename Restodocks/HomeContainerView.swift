import SwiftUI

struct HomeContainerView: View {

    @EnvironmentObject var accounts: AccountManager

    var body: some View {

        // позже тут будет логика по подразделению
        // сейчас — базовый Home

        HomeView()
    }
}