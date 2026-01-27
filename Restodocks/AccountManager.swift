import Foundation
import Combine

final class AccountManager: ObservableObject {

    @Published var establishment: EstablishmentAccount?
    @Published var owner: EmployeeAccount?
    @Published var currentEmployee: EmployeeAccount?
    @Published var isLoggedIn: Bool = false

    // MARK: - Company

    func createEstablishment(name: String, email: String) {
        let pin = Self.generateCompanyPin()

        establishment = EstablishmentAccount(
            name: name,
            email: email,
            pinCode: pin
        )

        print("✅ Company created. PIN:", pin)
    }

    // MARK: - Owner

    func createOwner(
        fullName: String,
        email: String,
        password: String,
        pin: String
    ) -> Bool {

        guard var est = establishment else { return false }
        guard est.pinCode == pin else { return false }
        guard owner == nil else { return false }

        let ownerAccount = EmployeeAccount(
            fullName: fullName,
            email: email,
            role: .owner,
            department: .management,
            birthDate: nil,
            pinCode: pin
        )

        owner = ownerAccount
        currentEmployee = ownerAccount
        isLoggedIn = true

        // ✅ сохраняем владельца в компании
        est.employees.append(ownerAccount)
        establishment = est

        return true
    }

    // MARK: - Employee Registration

    func registerEmployee(
        fullName: String,
        email: String,
        role: EmployeeRole,
        department: Department,
        birthDate: Date?,
        pin: String
    ) -> Bool {

        guard var est = establishment else { return false }
        guard est.pinCode == pin else { return false }

        let employee = EmployeeAccount(
            fullName: fullName,
            email: email,
            role: role,
            department: department,
            birthDate: birthDate,
            pinCode: pin
        )

        est.employees.append(employee)
        establishment = est

        currentEmployee = employee
        isLoggedIn = true

        return true
    }

    // MARK: - Login / Logout

    func login(pin: String) -> Bool {
        guard let est = establishment else { return false }
        guard est.pinCode == pin else { return false }

        currentEmployee = owner
        isLoggedIn = true
        return true
    }

    func logout() {
        currentEmployee = nil
        isLoggedIn = false
    }

    // MARK: - PIN

    private static func generateCompanyPin() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).compactMap { _ in chars.randomElement() })
    }
}
