//
//  ShiftRowView.swift
//  Restodocks
//

import SwiftUI

struct ShiftRowView: View {

    let shift: ShiftEntity

    var body: some View {

        HStack {

            VStack(alignment: .leading) {

                Text(shift.employee?.fullName ?? "—")
                    .font(.body)
                    .bold()

                if shift.fullDay {
                    Text("full_day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(shift.startHour):00 – \(shift.endHour):00")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
