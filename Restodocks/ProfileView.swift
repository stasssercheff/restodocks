import SwiftUI

struct ProfileView: View {

    @EnvironmentObject var accounts: AccountManager
    @ObservedObject var lang = LocalizationManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var showInviteAlert = false

    var body: some View {

        VStack(spacing: 20) {

            Text(lang.t("profile"))
                .font(.largeTitle)
                .bold()

            if let est = accounts.establishment {
                infoBlock(
                    title: lang.t("company"),
                    value: est.name
                )

                infoBlock(
                    title: lang.t("company_pin"),
                    value: est.pinCode,
                    mono: true
                )
            }

            if let emp = accounts.currentEmployee {
                infoBlock(
                    title: lang.t("name"),
                    value: emp.fullName
                )

                infoBlock(
                    title: lang.t("role"),
                    value: lang.t(emp.role.rawValue)
                )
            }

            Divider()

            // ✅ ПРАВИЛЬНО
            Button {
                showInviteAlert = true
            } label: {
                PrimaryButton(title: lang.t("invite_partner"))
            }

            Button(role: .destructive) {
                accounts.logout()
                dismiss()
            } label: {
                Text(lang.t("logout"))
            }

            Spacer()
        }
        .padding()
        .alert(lang.t("invite_partner"), isPresented: $showInviteAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lang.t("invite_partner_info"))
        }
    }

    private func infoBlock(
        title: String,
        value: String,
        mono: Bool = false
    ) -> some View {

        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(mono ? .system(.body, design: .monospaced) : .body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
