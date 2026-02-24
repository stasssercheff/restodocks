//
//  OrderMailComposerView.swift
//  Restodocks
//
//  Обёртка над MFMailComposeViewController для отправки заказа с вложением PDF.
//

import SwiftUI
import MessageUI

struct OrderMailComposerView: UIViewControllerRepresentable {

    let subject: String
    let body: String
    let pdfData: Data?
    let pdfFileName: String
    var onFinish: (() -> Void)?
    var onDismiss: (() -> Void)?

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard context.coordinator.presented == false else { return }
        context.coordinator.presented = true
        if !MFMailComposeViewController.canSendMail() {
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: nil,
                    message: NSLocalizedString("Mail is not configured on this device.", comment: ""),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
                    parent.onDismiss?()
                })
                uiViewController.present(alert, animated: true)
            }
            return
        }
        DispatchQueue.main.async {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = context.coordinator
            mail.setSubject(subject)
            mail.setMessageBody(body, isHTML: false)
            if let data = pdfData, !data.isEmpty {
                mail.addAttachmentData(data, mimeType: "application/pdf", fileName: pdfFileName)
            }
            uiViewController.present(mail, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var parent: OrderMailComposerView
        var presented = false

        init(_ parent: OrderMailComposerView) {
            self.parent = parent
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
            parent.onFinish?()
            parent.onDismiss?()
        }
    }
}
