import SwiftUI

struct CustomHomePlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "star")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("Здесь будет настраиваемая кнопка")
                .foregroundColor(.secondary)
        }
        .navigationTitle("Избранное")
    }
}