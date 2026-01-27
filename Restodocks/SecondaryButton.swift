import SwiftUI

struct SecondaryButton: View {

    let title: String

    var body: some View {
        Text(title)
            .foregroundColor(AppTheme.primary)
            .frame(maxWidth: .infinity)
            .padding()
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.primary, lineWidth: 1)
            )
    }
}
