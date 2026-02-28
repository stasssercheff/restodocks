//
//  Shift.swift
//  Restodocks
//

import Foundation

struct Shift: Codable, Identifiable {
    let id: UUID
    let date: Date
    var department: String?
    var startHour: Int16
    var endHour: Int16
    var fullDay: Bool
    let employeeId: UUID
    var createdAt: Date?
    var confirmedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case department
        case startHour = "start_hour"
        case endHour = "end_hour"
        case fullDay = "full_day"
        case employeeId = "employee_id"
        case createdAt = "created_at"
        case confirmedAt = "confirmed_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let dateStr = try c.decode(String.self, forKey: .date)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        date = fmt.date(from: String(dateStr.prefix(10))) ?? Date()
        department = try c.decodeIfPresent(String.self, forKey: .department)
        startHour = Int16(try c.decodeIfPresent(Int.self, forKey: .startHour) ?? 0)
        endHour = Int16(try c.decodeIfPresent(Int.self, forKey: .endHour) ?? 0)
        fullDay = try c.decodeIfPresent(Bool.self, forKey: .fullDay) ?? false
        employeeId = try c.decode(UUID.self, forKey: .employeeId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        confirmedAt = try c.decodeIfPresent(Date.self, forKey: .confirmedAt)
    }

    init(id: UUID, date: Date, department: String?, startHour: Int16, endHour: Int16, fullDay: Bool, employeeId: UUID, createdAt: Date?, confirmedAt: Date? = nil) {
        self.id = id
        self.date = date
        self.department = department
        self.startHour = startHour
        self.endHour = endHour
        self.fullDay = fullDay
        self.employeeId = employeeId
        self.createdAt = createdAt
        self.confirmedAt = confirmedAt
    }

    /// Смена считается "эффективной" (не выходным) если:
    /// - она подтверждена, ИЛИ
    /// - с момента смены прошло менее 72 часов (окно для подтверждения ещё открыто)
    var isEffective: Bool {
        if confirmedAt != nil { return true }
        let shiftEndOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
        let deadline = shiftEndOfDay.addingTimeInterval(72 * 3600)
        return Date() < deadline
    }
}
