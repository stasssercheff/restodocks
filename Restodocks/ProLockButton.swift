import SwiftUI

struct ProLockButton: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)

            Spacer()

            Image(systemName: "crown.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.accent)
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppTheme.shadow, radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
        )
    }
}
