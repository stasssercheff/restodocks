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
        }
    }
}
