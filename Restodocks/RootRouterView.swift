import SwiftUI

struct RootRouterView: View {

    @EnvironmentObject var accounts: AccountManager

    var body: some View {

        // ❗️ NavigationStack должен быть ОДИН — здесь
        NavigationStack {

            // 1️⃣ Нет компании — старт
            if accounts.establishment == nil {
                RegistrationChoiceView()
            }

            // 2️⃣ Компания есть, но владелец не создан
            else if accounts.owner == nil {
                CreateOwnerView(
                    companyPin: accounts.establishment!.pinCode
                )
            }

            // 3️⃣ Пользователь вошёл
            else if accounts.isLoggedIn {
                AppRoute()
            }

            // 4️⃣ Компания есть, но никто не вошёл → СТАРТ
            else {
                RegistrationChoiceView()
            }
        }
    }
}
