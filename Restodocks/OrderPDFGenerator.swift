//
//  OrderPDFGenerator.swift
//  Restodocks
//
//  Формирование PDF заказа в виде таблицы (сетка, колонки) для сохранения в файл.
//

import UIKit

enum OrderPDFGenerator {

    /// Генерирует PDF с заказом в виде таблицы: заголовок, дата, таблица с рамками (наименование | единица | количество).
    static func pdfData(
        orderLines: [OrderLine],
        title: String,
        date: Date = Date(),
        productColumnTitle: String = "Product",
        unitColumnTitle: String = "Unit",
        quantityColumnTitle: String = "Qty"
    ) -> Data? {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40
        let tableRowHeight: CGFloat = 26
        let headerHeight: CGFloat = 30
        let lineWidth: CGFloat = 0.5

        let colQuantityWidth: CGFloat = 72
        let colUnitWidth: CGFloat = 82
        let tableWidth = pageWidth - margin * 2
        let colNameWidth = tableWidth - colUnitWidth - colQuantityWidth
        let col1X = margin
        let col2X = col1X + colNameWidth
        let col3X = col2X + colUnitWidth

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "ru_RU")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let data = renderer.pdfData { context in
            var y = margin
            let titleFont = UIFont.boldSystemFont(ofSize: 18)
            let headerFont = UIFont.boldSystemFont(ofSize: 11)
            let bodyFont = UIFont.systemFont(ofSize: 10)
            let bodyAttr: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.black]
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            paragraphStyle.lineBreakMode = .byTruncatingTail
            let centerStyle = NSMutableParagraphStyle()
            centerStyle.alignment = .center

            func drawRect(_ rect: CGRect, fill: UIColor? = nil, stroke: Bool = true) {
                if let fill = fill {
                    fill.setFill()
                    UIBezierPath(rect: rect).fill()
                }
                if stroke {
                    UIColor.darkGray.setStroke()
                    let path = UIBezierPath(rect: rect)
                    path.lineWidth = lineWidth
                    path.stroke()
                }
            }

            // Заголовок
            (title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont, .foregroundColor: UIColor.black])
            y += 22

            // Дата
            let dateStr = dateFormatter.string(from: date)
            (dateStr as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.darkGray])
            y += 18

            let tableTopY = y

            // Заголовок таблицы (серая полоса)
            let headerRect = CGRect(x: col1X, y: y, width: tableWidth, height: headerHeight)
            drawRect(headerRect, fill: UIColor(white: 0.4, alpha: 1))
            (productColumnTitle as NSString).draw(in: CGRect(x: col1X + 6, y: y + 7, width: colNameWidth - 12, height: headerHeight - 14), withAttributes: [.font: headerFont, .foregroundColor: UIColor.white, .paragraphStyle: centerStyle])
            (unitColumnTitle as NSString).draw(in: CGRect(x: col2X + 6, y: y + 7, width: colUnitWidth - 12, height: headerHeight - 14), withAttributes: [.font: headerFont, .foregroundColor: UIColor.white, .paragraphStyle: centerStyle])
            (quantityColumnTitle as NSString).draw(in: CGRect(x: col3X + 6, y: y + 7, width: colQuantityWidth - 12, height: headerHeight - 14), withAttributes: [.font: headerFont, .foregroundColor: UIColor.white, .paragraphStyle: centerStyle])
            y += headerHeight

            // Рамка заголовка таблицы (вертикальные линии)
            drawRect(CGRect(x: col1X, y: tableTopY, width: lineWidth, height: headerHeight), fill: UIColor.darkGray, stroke: false)
            drawRect(CGRect(x: col2X, y: tableTopY, width: lineWidth, height: headerHeight), fill: UIColor.darkGray, stroke: false)
            drawRect(CGRect(x: col3X, y: tableTopY, width: lineWidth, height: headerHeight), fill: UIColor.darkGray, stroke: false)
            drawRect(CGRect(x: col1X + tableWidth - lineWidth, y: tableTopY, width: lineWidth, height: headerHeight), fill: UIColor.darkGray, stroke: false)

            for line in orderLines {
                if y + tableRowHeight > pageHeight - margin {
                    context.beginPage()
                    y = margin
                }
                let name = line.product.localizedName
                let unit = line.product.unit ?? "—"
                let qty = formatQuantity(line.quantity)

                // Горизонтальная линия сверху строки
                drawRect(CGRect(x: col1X, y: y, width: tableWidth, height: lineWidth), fill: UIColor.darkGray, stroke: false)
                // Ячейки
                (name as NSString).draw(in: CGRect(x: col1X + 6, y: y + 5, width: colNameWidth - 12, height: tableRowHeight - 10), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.black, .paragraphStyle: paragraphStyle])
                drawRect(CGRect(x: col2X, y: y, width: lineWidth, height: tableRowHeight), fill: UIColor.darkGray, stroke: false)
                (unit as NSString).draw(in: CGRect(x: col2X + 6, y: y + 5, width: colUnitWidth - 12, height: tableRowHeight - 10), withAttributes: bodyAttr)
                drawRect(CGRect(x: col3X, y: y, width: lineWidth, height: tableRowHeight), fill: UIColor.darkGray, stroke: false)
                (qty as NSString).draw(in: CGRect(x: col3X + 6, y: y + 5, width: colQuantityWidth - 12, height: tableRowHeight - 10), withAttributes: bodyAttr)
                drawRect(CGRect(x: col3X + colQuantityWidth - lineWidth, y: y, width: lineWidth, height: tableRowHeight), fill: UIColor.darkGray, stroke: false)
                y += tableRowHeight
            }
            // Левая граница таблицы на всю высоту данных
            drawRect(CGRect(x: col1X, y: tableTopY, width: lineWidth, height: y - tableTopY), fill: UIColor.darkGray, stroke: false)
            // Нижняя граница таблицы
            drawRect(CGRect(x: col1X, y: y, width: tableWidth, height: lineWidth), fill: UIColor.darkGray, stroke: false)
        }
        return data
    }

    private static func formatQuantity(_ q: Double) -> String {
        if q == floor(q) { return "\(Int(q))" }
        return String(format: "%.1f", q)
    }
}
