import SwiftUI

struct ManagementView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var appState: AppState

    private var currentEmployee: Employee? {
        accounts.currentEmployee ?? appState.currentEmployee
    }

    /// Собственник в режиме «должность» — показываем интерфейс его должности
    private var shouldShowPositionInterface: Bool {
        guard let emp = currentEmployee, emp.isOwnerWithPosition else { return false }
        return appState.ownerViewMode == "position"
    }

    /// Определяем подразделение сотрудника на основе его роли
    private var employeeDepartment: String? {
        guard let emp = currentEmployee else { return nil }

        // Шеф-повара и су-шефы - кухня
        if emp.rolesArray.contains("executive_chef") || emp.rolesArray.contains("sous_chef") {
            return "kitchen"
        }

        // Бар-менеджеры - бар
        if emp.rolesArray.contains("bar_manager") {
            return "bar"
        }

        // Менеджеры зала - зал
        if emp.rolesArray.contains("dining_manager") {
            return "dining_room"
        }

        // Общие менеджеры - используем department из профиля
        return emp.department == "kitchen" ? "kitchen" :
               emp.department == "bar" ? "bar" :
               emp.department == "dining_room" ? "dining_room" : nil
    }

    var body: some View {
        Group {
            if shouldShowPositionInterface, let position = currentEmployee?.jobPosition {
                // Интерфейс по выбранной должности
                positionView(for: position)
            } else {
                // Полный список (владелец в режиме «собственник» или обычный сотрудник)
                managementList
            }
        }
        .navigationTitle(lang.t("management"))
    }

    @ViewBuilder
    private func positionView(for position: String) -> some View {
        switch position {
        case "executive_chef", "sous_chef":
            ExecutiveChefView()
        case "manager", "dining_manager", "bar_manager", "director":
            GeneralManagerView()
        default:
            managementList
        }
    }

    private var managementList: some View {
        List {
            NavigationLink {
                ExecutiveChefView()
            } label: {
                HStack {
                    Image(systemName: "chef.hat")
                    Text(lang.t("executive_chef"))
                }
            }

            NavigationLink {
                GeneralManagerView()
            } label: {
                HStack {
                    Image(systemName: "person.badge.key")
                    Text(lang.t("general_manager"))
                }
            }

            // Кнопка просмотра ТТК для сотрудников управления (только своего подразделения)
            if appState.canManageSchedule, let dept = employeeDepartment {
                NavigationLink {
                    DepartmentTTKView(department: dept)
                } label: {
                    HStack {
                        Image(systemName: departmentIcon(for: dept))
                        Text(departmentTTKTitle(for: dept))
                        Text("(\(lang.t("view_only")))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func departmentIcon(for department: String) -> String {
        switch department {
        case "kitchen": return "🍳"
        case "bar": return "🍸"
        case "dining_room": return "🍽️"
        default: return "📋"
        }
    }

    private func departmentTTKTitle(for department: String) -> String {
        switch department {
        case "kitchen": return "ТТК кухни"
        case "bar": return "ТТК бара"
        case "dining_room": return "ТТК зала"
        default: return lang.t("view_ttk")
        }
    }
}
