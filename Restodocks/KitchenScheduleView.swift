//
//  KitchenScheduleView.swift
//  Restodocks
//

import SwiftUI
import CoreData

struct KitchenScheduleView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ShiftEntity.date, ascending: true)],
        animation: .default
    )
    private var shifts: FetchedResults<ShiftEntity>

    @State private var selectedDepartment: Department = .all
    @State private var selectedDate = Date()
    @State private var showingAddShift = false

    enum Department: String, CaseIterable, Identifiable {
        case all = "all"
        case hotKitchen = "hot_kitchen"
        case coldKitchen = "cold_kitchen"
        case grill = "grill"
        case pizza = "pizza"
        case sushiBar = "sushi_bar"
        case prep = "prep"
        case pastry = "pastry"
        case bakery = "bakery"
        case hall = "hall"
        case management = "management"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all: return "Все цеха"
            case .hotKitchen: return "Горячий цех"
            case .coldKitchen: return "Холодный цех"
            case .grill: return "Гриль"
            case .pizza: return "Пицца"
            case .sushiBar: return "Суши-бар"
            case .prep: return "Заготовка"
            case .pastry: return "Кондитерка"
            case .bakery: return "Выпечка"
            case .hall: return "Зал"
            case .management: return "Управление"
            }
        }

        var icon: String {
            switch self {
            case .all: return "🏢"
            case .hotKitchen: return "🔥"
            case .coldKitchen: return "❄️"
            case .grill: return "🍖"
            case .pizza: return "🍕"
            case .sushiBar: return "🍱"
            case .prep: return "🥕"
            case .pastry: return "🍰"
            case .bakery: return "🥖"
            case .hall: return "🍽️"
            case .management: return "👔"
            }
        }
    }

    var filteredShifts: [ShiftEntity] {
        shifts.filter { shift in
            // Filter by department
            if selectedDepartment != .all {
                return shift.department == selectedDepartment.rawValue
            }
            return true
        }
    }

    var shiftsByDate: [Date: [ShiftEntity]] {
        Dictionary(grouping: filteredShifts) { shift in
            Calendar.current.startOfDay(for: shift.date ?? Date())
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Department filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Department.allCases) { department in
                            DepartmentFilterButton(
                                department: department,
                                isSelected: selectedDepartment == department
                            ) {
                                selectedDepartment = department
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemBackground))

                // Schedule content
                if shiftsByDate.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text(lang.t("schedule_empty"))
                            .font(.title2)
                            .foregroundColor(.secondary)

                        Text(lang.t("add_first_shift"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(shiftsByDate.keys.sorted(), id: \.self) { date in
                                if let dayShifts = shiftsByDate[date], !dayShifts.isEmpty {
                                    DayScheduleCard(date: date, shifts: dayShifts)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle(lang.t("schedule"))
            .toolbar {
                if appState.canManageSchedule {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingAddShift = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddShift) {
                CreateShiftView()
            }
        }
    }
}

struct DepartmentFilterButton: View {
    let department: KitchenScheduleView.Department
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(department.icon)
                    .font(.title2)

                Text(department.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: 80, height: 60)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .foregroundColor(isSelected ? .blue : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
    }
}

struct DayScheduleCard: View {
    let date: Date
    let shifts: [ShiftEntity]

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date).capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(formattedDate)
                .font(.headline)
                .padding(.horizontal)

            ForEach(shifts, id: \.id) { shift in
                ShiftCard(shift: shift)
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
        .padding(.horizontal)
    }
}

struct ShiftCard: View {
    @EnvironmentObject var lang: LocalizationManager
    let shift: ShiftEntity

    var departmentInfo: (icon: String, name: String) {
        switch shift.department {
        case "hot_kitchen": return ("🔥", lang.t("hot_kitchen"))
        case "cold_kitchen": return ("❄️", lang.t("cold_kitchen"))
        case "grill": return ("🍖", lang.t("grill"))
        case "pizza": return ("🍕", lang.t("pizza"))
        case "sushi_bar": return ("🍱", lang.t("sushi_bar"))
        case "prep": return ("🥕", lang.t("prep"))
        case "pastry": return ("🍰", lang.t("pastry"))
        case "bakery": return ("🥖", lang.t("bakery"))
        case "hall": return ("🍽️", lang.t("dining_room"))
        case "management": return ("👔", lang.t("management"))
        default: return ("🏢", lang.t("unknown"))
        }
    }

    var timeString: String {
        if shift.fullDay {
            return lang.t("full_day_text")
        } else {
            return "\(shift.startHour):00 - \(shift.endHour):00"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Department icon
            Text(departmentInfo.icon)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(shift.employee?.fullName ?? lang.t("unknown"))
                    .font(.headline)

                HStack {
                    Text(departmentInfo.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(timeString)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}