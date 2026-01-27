import SwiftUI

struct HomeButton: View {

    let title: String
    var systemImage: String = "chevron.right"

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.primary)
        }
        .padding()
        .background(AppTheme.secondaryBackground)
        .cornerRadius(12)
    }
}
