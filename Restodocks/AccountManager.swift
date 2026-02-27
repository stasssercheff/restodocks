//
//  AccountManager.swift
//  Restodocks
//

import Foundation
import Combine
import Supabase

final class AccountManager: ObservableObject {

    private let client = SupabaseManager.shared.client

    weak var appState: AppState? {
        didSet {
            if appState != nil {
                syncAppState()
            }
        }
    }

    @Published var establishment: Establishment?
    @Published var currentEmployee: Employee? {
        didSet {
            LocalizationManager.shared.currentEmployeeId = currentEmployee?.id.uuidString
        }
    }
    @Published var employees: [Employee] = []
    @Published var shifts: [Shift] = []
    @Published var suppliers: [Supplier] = []
    @Published var savedOrders: [SavedOrder] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var emailConfirmed: Bool = false

    init() {
        Task {
            await loadSession()
        }
    }

    private func syncAppState() {
        if establishment != nil {
            appState?.isCompanyCreated = true
        }
        if currentEmployee != nil {
            appState?.isLoggedIn = true
        }
    }

    // MARK: - SESSION
    @MainActor
    private func loadSession() async {
        do {
            let session = try await client.auth.session

            // Check if email is confirmed
            guard let user = session.user, user.emailConfirmedAt != nil else {
                // Email not confirmed - sign out and don't load session
                try? await client.auth.signOut()
                return
            }

            let userId = session.user.id
            let employees: [Employee] = try await client
                .from("employees")
                .select()
                .eq("id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            if let emp = employees.first {
                currentEmployee = emp
                let establishments: [Establishment] = try await client
                    .from("establishments")
                    .select()
                    .eq("id", value: emp.establishmentId.uuidString)
                    .limit(1)
                    .execute()
                    .value
                establishment = establishments.first
                emailConfirmed = session.user?.emailConfirmedAt != nil
                appState?.isCompanyCreated = true
                appState?.isLoggedIn = true
                if let pin = establishment?.pinCode {
                    appState?.companyPinCode = pin
                }
                await fetchEmployees()
            }
        } catch {
            // Нет сессии — нормально при первом запуске
        }
    }

    @MainActor
    func fetchEmployees() async {
        guard let estId = establishment?.id else { employees = []; return }
        do {
            let list: [Employee] = try await client
                .from("employees")
                .select()
                .eq("establishment_id", value: estId.uuidString)
                .order("full_name", ascending: true)
                .execute()
                .value
            employees = list
        } catch {
            employees = []
        }
    }

    @MainActor
    func fetchShifts() async {
        guard !employees.isEmpty else { shifts = []; return }
        do {
            var all: [Shift] = []
            for emp in employees {
                let list: [Shift] = try await client
                    .from("shifts")
                    .select()
                    .eq("employee_id", value: emp.id.uuidString)
                    .execute()
                    .value
                all.append(contentsOf: list)
            }
            shifts = all.sorted { ($0.date, $0.startHour) < ($1.date, $1.startHour) }
        } catch {
            shifts = []
        }
    }

    @MainActor
    func createShift(employeeId: UUID, date: Date, department: String?, startHour: Int16, endHour: Int16, fullDay: Bool) async throws {
        struct ShiftInsert: Encodable {
            let employee_id: String
            let date: String
            let department: String?
            let start_hour: Int
            let end_hour: Int
            let full_day: Bool
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let shift = ShiftInsert(
            employee_id: employeeId.uuidString,
            date: formatter.string(from: date),
            department: department,
            start_hour: Int(startHour),
            end_hour: Int(endHour),
            full_day: fullDay
        )
        try await client.from("shifts").insert(shift).execute()
        await fetchShifts()
    }

    func employeeName(for id: UUID) -> String {
        employees.first { $0.id == id }?.fullName ?? "—"
    }

    func employeePosition(for id: UUID) -> String {
        guard let emp = employees.first(where: { $0.id == id }) else { return "—" }
        return emp.jobPosition ?? emp.roles.first ?? "—"
    }

    @MainActor
    func updateEmployeePayroll(employeeId: UUID, costPerUnit: Double, payrollCountingMode: String) async {
        do {
            try await client.from("employees")
                .update(["cost_per_unit": costPerUnit, "payroll_counting_mode": payrollCountingMode])
                .eq("id", value: employeeId.uuidString)
                .execute()
            await fetchEmployees()
        } catch {
            print("❌ Update employee error:", error)
        }
    }

    @MainActor
    func deleteEmployee(_ employee: Employee) async {
        do {
            try await client.from("employees")
                .delete()
                .eq("id", value: employee.id.uuidString)
                .execute()
            await fetchEmployees()
        } catch {
            print("❌ Delete employee error:", error)
        }
    }

    @MainActor
    func updateEmployee(
        _ employee: Employee,
        fullName: String,
        department: String,
        role: String,
        payMode: String,
        costPerUnit: Double
    ) async {
        struct EmployeeUpdate: Encodable {
            let full_name: String
            let department: String
            let roles: [String]
            let payroll_counting_mode: String
            let cost_per_unit: Double
        }
        do {
            let update = EmployeeUpdate(
                full_name: fullName,
                department: department,
                roles: [role],
                payroll_counting_mode: payMode,
                cost_per_unit: costPerUnit
            )
            try await client.from("employees")
                .update(update)
                .eq("id", value: employee.id.uuidString)
                .execute()
            await fetchEmployees()
        } catch {
            print("❌ Update employee error:", error)
        }
    }

    @MainActor
    func deleteShift(_ shift: Shift) async {
        do {
            try await client.from("shifts").delete().eq("id", value: shift.id.uuidString).execute()
            await fetchShifts()
        } catch {
            print("❌ Delete shift error:", error)
        }
    }

    // MARK: - SUPPLIERS
    @MainActor
    func fetchSuppliers() async {
        guard let estId = establishment?.id else { suppliers = []; return }
        do {
            let list: [Supplier] = try await client
                .from("suppliers")
                .select()
                .eq("establishment_id", value: estId.uuidString)
                .order("name", ascending: true)
                .execute()
                .value
            suppliers = list
        } catch {
            suppliers = []
        }
    }

    @MainActor
    func createSupplier(name: String, phone: String?, email: String?, address: String?, comment: String?) async throws {
        guard let estId = establishment?.id else {
            throw NSError(domain: "AccountManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No establishment"])
        }
        struct Insert: Encodable {
            let establishment_id: String
            let name: String
            let phone: String?
            let email: String?
            let address: String?
            let comment: String?
        }
        try await client.from("suppliers")
            .insert(Insert(
                establishment_id: estId.uuidString,
                name: name,
                phone: phone?.isEmpty == true ? nil : phone,
                email: email?.isEmpty == true ? nil : email,
                address: address?.isEmpty == true ? nil : address,
                comment: comment?.isEmpty == true ? nil : comment
            ))
            .execute()
        await fetchSuppliers()
    }

    @MainActor
    func updateSupplier(_ supplier: Supplier) async throws {
        struct Update: Encodable {
            let name: String
            let phone: String?
            let email: String?
            let address: String?
            let comment: String?
        }
        try await client.from("suppliers")
            .update(Update(
                name: supplier.name,
                phone: supplier.phone?.isEmpty == true ? nil : supplier.phone,
                email: supplier.email?.isEmpty == true ? nil : supplier.email,
                address: supplier.address?.isEmpty == true ? nil : supplier.address,
                comment: supplier.comment?.isEmpty == true ? nil : supplier.comment
            ))
            .eq("id", value: supplier.id.uuidString)
            .execute()
        await fetchSuppliers()
    }

    @MainActor
    func deleteSupplier(_ supplier: Supplier) async {
        do {
            try await client.from("suppliers").delete().eq("id", value: supplier.id.uuidString).execute()
            await fetchSuppliers()
        } catch {
            print("❌ Delete supplier error:", error)
        }
    }

    // MARK: - SAVED ORDERS (order_history)
    @MainActor
    func fetchSavedOrders() async {
        guard let estId = establishment?.id else { savedOrders = []; return }
        do {
            let list: [SavedOrder] = try await client
                .from("order_history")
                .select()
                .eq("establishment_id", value: estId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            savedOrders = list
        } catch {
            savedOrders = []
        }
    }

    @MainActor
    func createSavedOrder(lines: [OrderLinePayload]) async throws {
        guard let estId = establishment?.id, let empId = currentEmployee?.id else {
            throw NSError(domain: "AccountManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No establishment or employee"])
        }
        struct Insert: Encodable {
            let establishment_id: String
            let employee_id: String
            let order_data: [OrderLinePayload]
            let status: String
        }
        try await client.from("order_history")
            .insert(Insert(
                establishment_id: estId.uuidString,
                employee_id: empId.uuidString,
                order_data: lines,
                status: "saved"
            ))
            .execute()
        await fetchSavedOrders()
    }

    @MainActor
    func updateSavedOrder(_ order: SavedOrder) async throws {
        struct Update: Encodable {
            let order_data: [OrderLinePayload]
            let updated_at: String
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try await client.from("order_history")
            .update(Update(
                order_data: order.orderData,
                updated_at: fmt.string(from: Date())
            ))
            .eq("id", value: order.id.uuidString)
            .execute()
        await fetchSavedOrders()
    }

    @MainActor
    func deleteSavedOrder(_ order: SavedOrder) async {
        do {
            try await client.from("order_history").delete().eq("id", value: order.id.uuidString).execute()
            await fetchSavedOrders()
        } catch {
            print("❌ Delete order error:", error)
        }
    }

    // MARK: - COMPANY
    @MainActor
    func createEstablishment(name: String) async throws -> String {
        // 1. Регистрация владельца уже выполнена — получаем user
        guard let user = try? await client.auth.user() else {
            throw NSError(domain: "AccountManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        let pinCode = appState?.generatePinCode() ?? "0000"
        let establishmentId = UUID()

        let establishment: [String: AnyJSON] = [
            "id": .string(establishmentId.uuidString),
            "name": .string(name),
            "pin_code": .string(pinCode),
            "owner_id": .string(user.id.uuidString)
        ]

        try await client
            .from("establishments")
            .insert(establishment)
            .execute()

        self.establishment = Establishment(
            id: establishmentId,
            name: name,
            pinCode: pinCode,
            ownerId: user.id
        )
        appState?.isCompanyCreated = true
        appState?.companyPinCode = pinCode
        return pinCode
    }

    /// Создание компании и владельца (один вызов для Supabase)
    @MainActor
    func createCompanyAndOwner(
        companyName: String,
        fullName: String,
        email: String,
        password: String,
        ownerRole: String = "owner"
    ) async throws -> String {
        let pinCode = appState?.generatePinCode() ?? "0000"

        // 1. Регистрация в Supabase Auth
        let session = try await client.auth.signUp(
            email: email,
            password: password
        )
        guard let user = session.user else {
            throw NSError(domain: "AccountManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sign up failed"])
        }

        // 2. Создание заведения
        let establishmentId = UUID()
        let establishmentRow: [String: AnyJSON] = [
            "id": .string(establishmentId.uuidString),
            "name": .string(companyName),
            "pin_code": .string(pinCode),
            "owner_id": .string(user.id.uuidString)
        ]
        try await client.from("establishments").insert(establishmentRow).execute()

        // 3. Создание записи владельца в employees
        var roles = ["owner"]
        if ownerRole != "owner" { roles.append(ownerRole) }
        struct EmployeeInsert: Encodable {
            let id: String
            let full_name: String
            let email: String
            let password_hash: String
            let department: String
            let roles: [String]
            let establishment_id: String
            let personal_pin: String
            let is_active: Bool
        }
        let employeeInsert = EmployeeInsert(
            id: user.id.uuidString,
            full_name: fullName,
            email: email,
            password_hash: "auth",
            department: "management",
            roles: roles,
            establishment_id: establishmentId.uuidString,
            personal_pin: pinCode,
            is_active: true
        )
        try await client.from("employees").insert(employeeInsert).execute()

        self.establishment = Establishment(
            id: establishmentId,
            name: companyName,
            pinCode: pinCode,
            ownerId: user.id
        )
        self.currentEmployee = Employee(
            id: user.id,
            fullName: fullName,
            email: email,
            department: "management",
            roles: roles,
            establishmentId: establishmentId,
            personalPin: pinCode,
            isActive: true
        )
        appState?.isCompanyCreated = true
        appState?.isLoggedIn = true
        appState?.companyPinCode = pinCode
        appState?.currentEmployee = currentEmployee
        appState?.isCompanySelected = true
        await fetchEmployees()
        await fetchShifts()
        return pinCode
    }

    /// Устаревший метод — используйте createCompanyAndOwner
    @MainActor
    func createOwner(
        fullName: String,
        email: String,
        password: String
    ) async throws {
        guard let name = establishment?.name else {
            throw NSError(domain: "AccountManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Establishment required"])
        }
        _ = try await createCompanyAndOwner(
            companyName: name,
            fullName: fullName,
            email: email,
            password: password
        )
    }

    // MARK: - EMPLOYEE REGISTRATION (owner creates employee)
    @MainActor
    func createEmployeeForCompany(
        establishmentId: UUID,
        fullName: String,
        email: String,
        password: String,
        department: String,
        role: String
    ) async throws {
        let personalPin = appState?.generatePinCode() ?? "0000"

        // 1. Регистрация в Supabase Auth
        let session = try await client.auth.signUp(
            email: email,
            password: password
        )
        guard let user = session.user else {
            throw NSError(domain: "AccountManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sign up failed"])
        }

        // 2. Создание записи сотрудника
        struct EmployeeInsert: Encodable {
            let id: String
            let full_name: String
            let email: String
            let password_hash: String
            let department: String
            let roles: [String]
            let establishment_id: String
            let personal_pin: String
            let is_active: Bool
        }
        let employeeInsert = EmployeeInsert(
            id: user.id.uuidString,
            full_name: fullName,
            email: email,
            password_hash: "auth",
            department: department,
            roles: [role],
            establishment_id: establishmentId.uuidString,
            personal_pin: personalPin,
            is_active: true
        )
        try await client.from("employees").insert(employeeInsert).execute()

        self.currentEmployee = Employee(
            id: user.id,
            fullName: fullName,
            email: email,
            department: department,
            roles: [role],
            establishmentId: establishmentId,
            personalPin: personalPin,
            isActive: true
        )
        appState?.isLoggedIn = true
    }

    // MARK: - COMPANY SEARCH
    func findCompanyByName(_ name: String) async throws -> Establishment? {
        let req: [Establishment] = try await client
            .from("establishments")
            .select()
            .ilike("name", pattern: name)
            .limit(1)
            .execute()
            .value
        return req.first
    }

    func findCompanyByPinCode(_ pinCode: String) async throws -> Establishment? {
        let trimmed = pinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let req: [Establishment] = try await client
            .from("establishments")
            .select()
            .eq("pin_code", value: trimmed)
            .limit(1)
            .execute()
            .value
        return req.first
    }

    // MARK: - EMAIL CONFIRMATION
    func resendConfirmationEmail(email: String) async throws {
        try await client.auth.resend(
            email: email,
            type: .signup
        )
    }

    // MARK: - EMPLOYEE LOGIN (email + password)
    @MainActor
    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(
            email: email,
            password: password
        )

        // Check if email is confirmed
        guard let user = session.user, user.emailConfirmedAt != nil else {
            try? await client.auth.signOut()
            throw NSError(domain: "AccountManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Email not confirmed. Please check your email and click the confirmation link."])
        }

        let userId = session.user.id

        let employees: [Employee] = try await client
            .from("employees")
            .select()
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value

        guard let emp = employees.first else {
            try? await client.auth.signOut()
            throw NSError(domain: "AccountManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Employee not found"])
        }

        let establishments: [Establishment] = try await client
            .from("establishments")
            .select()
            .eq("id", value: emp.establishmentId.uuidString)
            .limit(1)
            .execute()
            .value

        guard let company = establishments.first else {
            try? await client.auth.signOut()
            throw NSError(domain: "AccountManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Establishment not found"])
        }

        currentEmployee = emp
        establishment = company
        emailConfirmed = session.user?.emailConfirmedAt != nil
        appState?.currentEmployee = emp
        appState?.isLoggedIn = true
        appState?.isCompanySelected = true
        appState?.companyPinCode = company.pinCode
        await fetchEmployees()
        await fetchShifts()
    }

    // MARK: - LOGOUT
    @MainActor
    func logout() async {
        try? await client.auth.signOut()
        currentEmployee = nil
        establishment = nil
        appState?.isLoggedIn = false
        appState?.currentEmployee = nil
    }

}
