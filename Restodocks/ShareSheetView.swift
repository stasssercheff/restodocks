//
//  ShareSheetView.swift
//  Restodocks
//
//  Показ системного share sheet для сохранения/отправки PDF (Файлы, почта и т.д.).
//

import SwiftUI
import UIKit

struct ShareSheetView: UIViewControllerRepresentable {

    let fileURL: URL
    var onDismiss: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        vc.completionWithItemsHandler = { _, _, _, _ in
            onDismiss?()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
