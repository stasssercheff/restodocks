//
//  AccountManager.swift
//  Restodocks
//

import Foundation
import CoreData
import Combine

final class AccountManager: ObservableObject {

    private let context =
        PersistenceController.shared.container.viewContext

    // связь с AppState (НЕ дублируем логику)
    weak var appState: AppState? {
        didSet {
            // ✅ Sync AppState when connection is established
            if appState != nil {
                syncAppState()
            }
        }
    }

    @Published var establishment: EstablishmentEntity?
    @Published var currentEmployee: EmployeeEntity?

    init() {
        loadEstablishment()
        loadActiveEmployee()
    }
    
    // MARK: - SYNC
    private func syncAppState() {
        if establishment != nil {
            appState?.isCompanyCreated = true
        }
        if currentEmployee != nil {
            appState?.isLoggedIn = true
        }
    }

    // MARK: - COMPANY
    func createEstablishment(name: String) -> String {

        let entity = EstablishmentEntity(context: context)
        entity.id = UUID()
        entity.name = name

        // Генерируем PIN код через AppState
        let pinCode = appState?.generatePinCode() ?? "0000"
        entity.pinCode = pinCode

        saveContext()

        establishment = entity
        appState?.isCompanyCreated = true

        return pinCode
    }

    // MARK: - OWNER
    func createOwner(
        fullName: String,
        email: String,
        password: String
    ) {
        guard let company = establishment else { return }

        let owner = EmployeeEntity(context: context)
        owner.id = UUID()
        owner.fullName = fullName
        owner.email = email
        owner.password = password
        owner.rolesArray = ["owner"]
        owner.isActive = true
        owner.pinCode = company.pinCode
        owner.department = "management"
        owner.establishment = company  // ✅ Set relationship

        saveContext()

        currentEmployee = owner
        appState?.isLoggedIn = true
    }

    // MARK: - EMPLOYEE
    func createEmployee(
        fullName: String,
        email: String,
        password: String,
        department: String,
        role: String
    ) {
        guard let company = establishment else { return }

        let employee = EmployeeEntity(context: context)
        employee.id = UUID()
        employee.fullName = fullName
        employee.email = email
        employee.password = password
        employee.department = department
        employee.rolesArray = [role]
        employee.isActive = true
        employee.pinCode = appState?.generatePinCode() ?? "0000" // Генерируем персональный PIN
        employee.establishment = company

        print("👥 createEmployeeForCompany: saved employee \(fullName) with roles \(employee.rolesArray)")

        saveContext()

        currentEmployee = employee
        appState?.isLoggedIn = true
    }

    // MARK: - EMPLOYEE REGISTRATION FOR EXISTING COMPANY
    func createEmployeeForCompany(
        _ company: EstablishmentEntity,
        fullName: String,
        email: String,
        password: String,
        department: String,
        role: String
    ) {
        let employee = EmployeeEntity(context: context)
        employee.id = UUID()
        employee.fullName = fullName
        employee.email = email
        employee.password = password
        employee.department = department
        employee.rolesArray = [role]
        employee.isActive = true
        employee.pinCode = appState?.generatePinCode() ?? "0000" // Персональный PIN сотрудника
        employee.establishment = company

        saveContext()

        currentEmployee = employee
        establishment = company
        appState?.currentEmployee = employee
        appState?.isCompanyCreated = true
        appState?.isLoggedIn = true
    }

    // MARK: - COMPANY SEARCH
    func findCompanyByName(_ name: String) -> EstablishmentEntity? {
        let req: NSFetchRequest<EstablishmentEntity> = EstablishmentEntity.fetchRequest()
        req.predicate = NSPredicate(format: "name ==[c] %@", name)
        req.fetchLimit = 1
        return try? context.fetch(req).first
    }

    func findCompanyByPinCode(_ pinCode: String) -> EstablishmentEntity? {
        let req: NSFetchRequest<EstablishmentEntity> = EstablishmentEntity.fetchRequest()
        req.predicate = NSPredicate(format: "pinCode ==[c] %@", pinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        req.fetchLimit = 1
        return try? context.fetch(req).first
    }

    // MARK: - EMPLOYEE LOGIN
    func findEmployeeByPinCode(_ pinCode: String) -> EmployeeEntity? {
        let req: NSFetchRequest<EmployeeEntity> = EmployeeEntity.fetchRequest()
        req.predicate = NSPredicate(format: "pinCode == %@", pinCode)
        return try? context.fetch(req).first
    }

    func findEmployeeByEmailAndPassword(_ email: String, _ password: String, inCompany company: EstablishmentEntity) -> EmployeeEntity? {
        let req: NSFetchRequest<EmployeeEntity> = EmployeeEntity.fetchRequest()
        req.predicate = NSPredicate(format: "email ==[c] %@ AND password == %@ AND establishment == %@", email, password, company)
        req.fetchLimit = 1
        return try? context.fetch(req).first
    }

    // MARK: - LOAD
    private func loadEstablishment() {
        let req: NSFetchRequest<EstablishmentEntity> =
            EstablishmentEntity.fetchRequest()
        req.fetchLimit = 1
        establishment = try? context.fetch(req).first

        if let company = establishment {
            appState?.isCompanyCreated = true
            // Загружаем PIN код из Core Data в AppState
            if let pinCode = company.pinCode {
                appState?.companyPinCode = pinCode
            }
        }
    }

    private func loadActiveEmployee() {
        let req: NSFetchRequest<EmployeeEntity> =
            EmployeeEntity.fetchRequest()
        req.predicate = NSPredicate(format: "isActive == YES")
        req.fetchLimit = 1

        if let emp = try? context.fetch(req).first {
            currentEmployee = emp
            appState?.isLoggedIn = true
        }
    }

    func logout() {
        currentEmployee?.isActive = false
        saveContext()
        currentEmployee = nil
        appState?.isLoggedIn = false
    }

    func saveContext() {
        try? context.save()
    }

    private static func generatePin() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).compactMap { _ in chars.randomElement() })
    }
}
