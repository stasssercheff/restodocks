//
//  NavigationHelpers.swift
//  Restodocks
//
//  Вспомогательные функции для навигации: переход на домашний экран, pop to root.
//

import SwiftUI
import UIKit

/// Переход на корневой экран текущей вкладки (для кнопки «Домой» в toolbar).
func popCurrentNavigationToRoot() {
    guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }),
          let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
          let root = window.rootViewController else { return }
    
    var vc: UIViewController? = root
    while let presented = vc?.presentedViewController { vc = presented }
    
    // Таб-бар: берём выбранную вкладку и в ней ищем UINavigationController
    if let tab = vc as? UITabBarController {
        vc = tab.selectedViewController
    }
    
    // Ищем UINavigationController в иерархии (SwiftUI NavigationStack под капотом даёт nav controller)
    var nav: UINavigationController?
    func findNav(_ controller: UIViewController?) {
        guard let c = controller else { return }
        if let n = c as? UINavigationController {
            nav = n
            return
        }
        for child in c.children {
            findNav(child)
            if nav != nil { return }
        }
    }
    findNav(vc)
    
    if let nav = nav, nav.viewControllers.count > 1 {
        nav.popToRootViewController(animated: true)
    }
}

// MARK: - Environment key для кнопки «Домой»

struct PopToRootKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var popToRoot: () -> Void {
        get { self[PopToRootKey.self] }
        set { self[PopToRootKey.self] = newValue }
    }
}

// MARK: - Кнопка «Домой» для toolbar

struct HomeToolbarButton: View {
    @EnvironmentObject var lang: LocalizationManager
    /// Если передан action — вызывается он, иначе вызывается глобальный popCurrentNavigationToRoot().
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button {
            if let action = action {
                action()
            } else {
                popCurrentNavigationToRoot()
            }
        } label: {
            Image(systemName: "house.fill")
        }
        .accessibilityLabel(lang.t("home"))
    }
}
