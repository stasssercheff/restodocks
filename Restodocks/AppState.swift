//
//  AppState.swift
//  Restodocks
//

import Foundation
import Combine

final class AppState: ObservableObject {

    private let userDefaults = UserDefaults.standard

    /// компания создана (сохраняется между запусками)
    @Published var isCompanyCreated: Bool = false {
        didSet {
            userDefaults.set(isCompanyCreated, forKey: "is_company_created")
            objectWillChange.send()
        }
    }

    /// компания выбрана/найдена (сохраняется между запусками)
    @Published var isCompanySelected: Bool = false {
        didSet {
            userDefaults.set(isCompanySelected, forKey: "company_selected")
            objectWillChange.send()
        }
    }

    /// PIN код компании (сохраняется между запусками)
    @Published var companyPinCode: String = "" {
        didSet {
            userDefaults.set(companyPinCode, forKey: "company_pin_code")
            objectWillChange.send()
        }
    }

    /// пользователь вошёл (владелец или сотрудник) - сохраняется между запусками
    @Published var isLoggedIn: Bool = false {
        didSet {
            userDefaults.set(isLoggedIn, forKey: "is_logged_in")
            objectWillChange.send()
        }
    }

    /// текущий пользователь (не сохраняется, восстанавливается из Core Data)
    @Published var currentEmployee: EmployeeEntity? {
        didSet {
            objectWillChange.send()
            if let employee = currentEmployee {
                print("👤 currentEmployee set: \(employee.fullName ?? "unknown"), roles: \(employee.rolesArray)")
            } else {
                print("👤 currentEmployee set to nil")
            }
        }
    }

    /// текущий PIN код для входа (не сохраняется)
    @Published var currentLoginPin: String = ""

    /// валюта для цен продуктов (сохраняется)
    var defaultCurrency: String {
        get { userDefaults.string(forKey: "default_currency") ?? "RUB" }
        set {
            userDefaults.set(newValue, forKey: "default_currency")
            objectWillChange.send()
        }
    }

    init() {
        // Загружаем сохраненные значения при инициализации
        isCompanyCreated = userDefaults.bool(forKey: "is_company_created")
        isCompanySelected = userDefaults.bool(forKey: "company_selected")
        companyPinCode = userDefaults.string(forKey: "company_pin_code") ?? ""
        isLoggedIn = userDefaults.bool(forKey: "is_logged_in")
    }

    /// проверка PIN кода
    func validatePinCode(_ pinCode: String) -> Bool {
        return pinCode == companyPinCode && !companyPinCode.isEmpty
    }

    /// генерация случайного буквенно-цифрового PIN кода (8 символов)
    func generatePinCode() -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let pin = String((0..<8).map { _ in characters.randomElement()! })
        companyPinCode = pin
        return pin
    }

    /// проверка прав на управление графиком, создание ТТК и карточек блюд
    var canManageSchedule: Bool {
        guard let employee = currentEmployee else {
            print("❌ canManageSchedule: currentEmployee is nil")
            return false
        }
        let roles = employee.rolesArray
        print("🔍 canManageSchedule: employee \(employee.fullName ?? "unknown"), roles: \(roles)")

        // Владелец всегда может управлять графиком
        if roles.contains("owner") {
            print("✅ canManageSchedule: access granted (owner)")
            return true
        }

        // Для кухни: шеф-повар и су-шеф (могут управлять графиком, создавать ТТК и карточки блюд)
        if roles.contains("executive_chef") || roles.contains("sous_chef") {
            print("✅ canManageSchedule: access granted (kitchen management)")
            return true
        }

        // Для остальных: менеджер и управляющий
        if roles.contains("manager") || roles.contains("dining_manager") || roles.contains("bar_manager") {
            print("✅ canManageSchedule: access granted (manager)")
            return true
        }

        print("❌ canManageSchedule: access denied")
        return false
    }

    /// проверка прав на просмотр определенного подразделения
    func canViewDepartment(_ department: String) -> Bool {
        guard let employee = currentEmployee else { return false }
        let userDepartment = employee.department
        let roles = employee.rolesArray

        // Владелец видит все
        if roles.contains("owner") { return true }

        // Руководители видят свое подразделение
        if roles.contains("manager") || roles.contains("sous_chef") ||
           roles.contains("dining_manager") || roles.contains("bar_manager") {
            return userDepartment == department || userDepartment == "management"
        }

        // Обычные сотрудники видят только свое подразделение
        return userDepartment == department
    }

    /// сброс состояния (для тестирования)
    func reset() {
        isCompanyCreated = false
        isCompanySelected = false
        companyPinCode = ""
        isLoggedIn = false
        currentLoginPin = ""

        // Очищаем UserDefaults
        userDefaults.removeObject(forKey: "is_company_created")
        userDefaults.removeObject(forKey: "company_selected")
        userDefaults.removeObject(forKey: "company_pin_code")
        userDefaults.removeObject(forKey: "is_logged_in")
    }
}
