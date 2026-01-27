import Foundation

struct EmployeeAccount: Codable, Identifiable {
    var id: UUID = UUID()
    var fullName: String
    var role: EmployeeRole
    var pinCode: String // или пароль
}
