import SwiftUI

struct AppNavigationView<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        NavigationStack {
            content
                // Удаляем отсюда любые .toolbar и .navigationTitle!
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
