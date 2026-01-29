import SwiftUI

struct PrimaryButton: View {

    let title: String
    var isDisabled: Bool = false
    var action: (() -> Void)? = nil

    private var backgroundView: some View {
        Group {
            if isDisabled {
                AppTheme.disabled
            } else {
                LinearGradient(
                    colors: [AppTheme.primary, AppTheme.primaryLight],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var shadowColor: Color {
        isDisabled ? .clear : AppTheme.primary.opacity(0.3)
    }

    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    buttonContent
                }
                .disabled(isDisabled)
            } else {
                buttonContent
            }
        }
    }

    private var buttonContent: some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(isDisabled ? AppTheme.disabled : AppTheme.textOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(backgroundView)
            .cornerRadius(16)
            .shadow(color: shadowColor, radius: 8, y: 4)
    }
}
