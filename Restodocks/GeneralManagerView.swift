//
//  GeneralManagerView.swift
//  Restodocks
//

import SwiftUI

struct GeneralManagerView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        List {
            // Dining room schedule (with editing capability)
            NavigationLink {
                ScheduleView() // TODO: Add editing capability for General Manager
            } label: {
                HStack {
                    Image(systemName: "calendar.badge.exclamationmark")
                    Text(lang.t("dining_room_schedule_editable"))
                }
            }
        }
        .navigationTitle(lang.t("general_manager"))
    }
}
