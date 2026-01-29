import SwiftUI

struct ProUnlockView: View {
    @EnvironmentObject var pro: ProAccess
    @EnvironmentObject var lang: LocalizationManager

    @State private var code: String = ""
    @State private var wrongCode: Bool = false

    var body: some View {
        AppNavigationView {
            VStack(spacing: 24) {

                // Crown icon
                Image(systemName: "crown.fill")
                    .font(.system(size: 60))
                    .foregroundColor(AppTheme.accent)
                    .padding(.top, 20)

                Text(lang.t("pro_features"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)

                Text(lang.t("pro_enter_or_buy"))
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal)

                VStack(spacing: 16) {
                    TextField(lang.t("enter_code"), text: $code)
                        .font(.system(size: 16))
                        .padding(16)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(wrongCode ? AppTheme.error : AppTheme.border, lineWidth: 1)
                        )
                        .padding(.horizontal)

                    if wrongCode {
                        Text(lang.t("wrong_code"))
                            .foregroundColor(AppTheme.error)
                            .font(.system(size: 14))
                    }

                    Button {
                        if pro.activateWithCode(code) {
                            wrongCode = false
                        } else {
                            wrongCode = true
                        }
                    } label: {
                        Text(lang.t("activate"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accentSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: AppTheme.accent.opacity(0.3), radius: 6, y: 3)
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .background(AppTheme.background)
            .navigationTitle(lang.t("pro_features"))
        }
    }
}
