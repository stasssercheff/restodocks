// SplashView.swift
import SwiftUI

struct SplashView: View {

    @State private var isActive = false

    var body: some View {
        Group {
            if isActive {
                RootRouterView()
            } else {
                VStack {
                    Spacer()
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.35)) {
                    isActive = true
                }
            }
        }
    }
}
