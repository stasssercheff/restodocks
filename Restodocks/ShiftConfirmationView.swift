//
//  ShiftConfirmationView.swift
//  Restodocks
//

import SwiftUI

struct ShiftConfirmationView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager

    private let confirmationWindowHours: Double = 72

    // Смены у которых окно подтверждения ещё открыто (прошло <72ч) и они не подтверждены
    private var pendingShifts: [Shift] {
        let now = Date()
        return accounts.shifts.filter { shift in
            guard shift.confirmedAt == nil else { return false }
            let shiftEndOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: shift.date) ?? shift.date
            let deadline = shiftEndOfDay.addingTimeInterval(confirmationWindowHours * 3600)
            return shift.date <= now && now < deadline
        }.sorted { $0.date < $1.date }
    }

    // Подтверждённые смены (последние 30 дней)
    private var confirmedShifts: [Shift] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return accounts.shifts.filter { $0.confirmedAt != nil && $0.date >= cutoff }
            .sorted { $0.date > $1.date }
    }

    // Просроченные без подтверждения (прошло >72ч, не подтверждены)
    private var expiredShifts: [Shift] {
        let now = Date()
        return accounts.shifts.filter { shift in
            guard shift.confirmedAt == nil else { return false }
            let shiftEndOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: shift.date) ?? shift.date
            let deadline = shiftEndOfDay.addingTimeInterval(confirmationWindowHours * 3600)
            return shift.date <= now && now >= deadline
        }.sorted { $0.date > $1.date }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM, EEEE"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        List {
            if pendingShifts.isEmpty && confirmedShifts.isEmpty && expiredShifts.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("Нет смен для подтверждения")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
                .listRowBackground(Color.clear)
            }

            if !pendingShifts.isEmpty {
                Section {
                    ForEach(pendingShifts) { shift in
                        ShiftConfirmRow(
                            shift: shift,
                            employeeName: accounts.employeeName(for: shift.employeeId),
                            status: .pending,
                            onConfirm: {
                                Task { await accounts.confirmShift(shift) }
                            }
                        )
                    }
                } header: {
                    Label("Ожидают подтверждения (\(pendingShifts.count))", systemImage: "clock.badge.exclamationmark")
                        .foregroundColor(.orange)
                }
            }

            if !expiredShifts.isEmpty {
                Section {
                    ForEach(expiredShifts) { shift in
                        ShiftConfirmRow(
                            shift: shift,
                            employeeName: accounts.employeeName(for: shift.employeeId),
                            status: .expired,
                            onConfirm: {
                                Task { await accounts.confirmShift(shift) }
                            }
                        )
                    }
                } header: {
                    Label("Просрочены — засчитываются как выходной (\(expiredShifts.count))", systemImage: "xmark.circle")
                        .foregroundColor(.red)
                }
            }

            if !confirmedShifts.isEmpty {
                Section {
                    ForEach(confirmedShifts) { shift in
                        ShiftConfirmRow(
                            shift: shift,
                            employeeName: accounts.employeeName(for: shift.employeeId),
                            status: .confirmed,
                            onConfirm: {}
                        )
                    }
                } header: {
                    Label("Подтверждены — последние 30 дней", systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                }
            }
        }
        .navigationTitle("Подтверждение смен")
        .task {
            await accounts.fetchEmployees()
            await accounts.fetchShifts()
        }
    }
}

// MARK: - Row

private enum ConfirmStatus {
    case pending, confirmed, expired
}

private struct ShiftConfirmRow: View {
    let shift: Shift
    let employeeName: String
    let status: ConfirmStatus
    let onConfirm: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM, EEEE"
        return f
    }()

    private var timeString: String {
        if shift.fullDay { return "Весь день" }
        return "\(shift.startHour):00 – \(shift.endHour):00"
    }

    private var deadlineString: String {
        let shiftEndOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: shift.date) ?? shift.date
        let deadline = shiftEndOfDay.addingTimeInterval(72 * 3600)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.dateFormat = "d MMM HH:mm"
        return "до \(fmt.string(from: deadline))"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(employeeName)
                    .font(.headline)

                Text(Self.dateFormatter.string(from: shift.date))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Text(timeString)
                        .font(.caption)
                        .foregroundColor(.blue)

                    if let dept = shift.department {
                        Text("· \(dept.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if status == .pending {
                    Text(deadlineString)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                if let confirmedAt = shift.confirmedAt {
                    let fmt = DateFormatter()
                    let _ = { fmt.locale = Locale(identifier: "ru_RU"); fmt.dateFormat = "d MMM HH:mm" }()
                    Text("Подтверждено: \(fmt.string(from: confirmedAt))")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            switch status {
            case .confirmed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)

            case .expired:
                Button(action: onConfirm) {
                    Text("Подтвердить")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

            case .pending:
                Button(action: onConfirm) {
                    Text("Подтвердить")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
