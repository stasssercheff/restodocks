import SwiftUI

struct SecondaryButton: View {

    let title: String
    var isDisabled: Bool = false
    var action: (() -> Void)? = nil

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
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(isDisabled ? AppTheme.disabled : AppTheme.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(AppTheme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isDisabled ? AppTheme.disabled : AppTheme.primary, lineWidth: 2)
            )
            .cornerRadius(16)
    }
}
