//
//  ShiftRowView.swift
//  Restodocks
//

import SwiftUI

struct ShiftRowView: View {

    let shift: WorkShift

    var body: some View {

        HStack {

            VStack(alignment: .leading) {
                Text(shift.employeeName)
                    .font(.body)
                    .bold()

                if !shift.fullDay,
                   let start = shift.startTime,
                   let end = shift.endTime {
                    Text("\(start) – \(end)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("full_day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}