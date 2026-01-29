import SwiftUI

struct HomeButton: View {

    let title: String
    var systemImage: String = "chevron.right"
    var isPro: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)

            Spacer()

            if isPro {
                Text("PRO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.trailing, 4)
            }

            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppTheme.shadow, radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}
