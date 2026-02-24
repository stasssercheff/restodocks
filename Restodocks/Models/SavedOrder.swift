//
//  SavedOrder.swift
//  Restodocks
//

import Foundation

/// Одна строка заказа в сохранённом документе (для JSONB order_data).
struct OrderLinePayload: Codable {
    var productId: UUID
    var productName: String
    var unit: String?
    var quantity: Double

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case productName = "product_name"
        case unit
        case quantity
    }
}

/// Сохранённый заказ продуктов (order_history).
struct SavedOrder: Codable, Identifiable {
    let id: UUID
    let establishmentId: UUID
    var employeeId: UUID?
    var orderData: [OrderLinePayload]
    var status: String
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case establishmentId = "establishment_id"
        case employeeId = "employee_id"
        case orderData = "order_data"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        establishmentId = try c.decode(UUID.self, forKey: .establishmentId)
        employeeId = try c.decodeIfPresent(UUID.self, forKey: .employeeId)
        orderData = try c.decode([OrderLinePayload].self, forKey: .orderData)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "sent"
        createdAt = try Self.decodeOptionalDate(c, forKey: .createdAt)
        updatedAt = try Self.decodeOptionalDate(c, forKey: .updatedAt)
    }

    private static func decodeOptionalDate(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let date = try c.decodeIfPresent(Date.self, forKey: key) { return date }
        if let str = try c.decodeIfPresent(String.self, forKey: key) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fmt.date(from: str) ?? ISO8601DateFormatter().date(from: str)
        }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(establishmentId, forKey: .establishmentId)
        try c.encodeIfPresent(employeeId, forKey: .employeeId)
        try c.encode(orderData, forKey: .orderData)
        try c.encode(status, forKey: .status)
    }

    init(id: UUID, establishmentId: UUID, employeeId: UUID?, orderData: [OrderLinePayload], status: String, createdAt: Date?, updatedAt: Date?) {
        self.id = id
        self.establishmentId = establishmentId
        self.employeeId = employeeId
        self.orderData = orderData
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
