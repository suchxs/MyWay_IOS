// Marker/label bitmaps for the map — the Swift port of MapMarkers.kt's buildLabelBitmap / buildPencilBitmap
// and TripLayer's avatar marker. Rendered as UIImages and set as GMSMarker icons.
import UIKit

enum MarkerImages {
    static let labelZoom: Float = 12   // note cards collapse to a pencil below this zoom (MapMarkers.LABEL_ZOOM)

    /// Rounded note card: bold title + teal note (prefixed with the settings note icon).
    static func noteCard(title: String, note: String, noteIcon: String, dark: Bool) -> UIImage {
        let padH: CGFloat = 12, padV: CGFloat = 9, lineGap: CGFloat = 4, shadow: CGFloat = 6, radius: CGFloat = 12
        let hasTitle = !title.isEmpty, hasNote = !note.isEmpty
        let noteText = hasNote ? "\(noteIcon) \(note)" : ""
        let titleFont = UIFont.boldSystemFont(ofSize: 12)
        let noteFont = UIFont.systemFont(ofSize: 11)
        let titleColor = dark ? UIColor(white: 0.95, alpha: 1) : UIColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1)
        let noteColor = dark ? UIColor(red: 0.176, green: 0.831, blue: 0.749, alpha: 1) : UIColor(red: 0, green: 0.655, blue: 0.49, alpha: 1)
        let cardColor = dark ? UIColor(red: 0.141, green: 0.196, blue: 0.267, alpha: 1) : .white
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
        let noteAttrs: [NSAttributedString.Key: Any] = [.font: noteFont, .foregroundColor: noteColor]
        let titleSize = hasTitle ? (title as NSString).size(withAttributes: titleAttrs) : .zero
        let noteSize = hasNote ? (noteText as NSString).size(withAttributes: noteAttrs) : .zero
        let textW = max(titleSize.width, noteSize.width)
        let gap = (hasTitle && hasNote) ? lineGap : 0
        let cardW = textW + padH * 2
        let cardH = padV * 2 + titleSize.height + noteSize.height + gap
        let w = cardW + shadow * 2, h = cardH + shadow * 2

        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            let rect = CGRect(x: shadow, y: shadow, width: cardW, height: cardH)
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: shadow, color: UIColor.black.withAlphaComponent(0.25).cgColor)
            cardColor.setFill(); UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            let x = shadow + padH
            var top = shadow + padV
            if hasTitle { (title as NSString).draw(at: CGPoint(x: x, y: top), withAttributes: titleAttrs); top += titleSize.height + gap }
            if hasNote { (noteText as NSString).draw(at: CGPoint(x: x, y: top), withAttributes: noteAttrs) }
        }
    }

    /// Collapsed note: a small circle with the settings pencil glyph.
    static func pencil(glyph: String, dark: Bool) -> UIImage {
        let size: CGFloat = 32
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let bg = dark ? UIColor(red: 0.141, green: 0.196, blue: 0.267, alpha: 1) : .white
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 4, color: UIColor.black.withAlphaComponent(0.2).cgColor)
            bg.setFill(); UIBezierPath(ovalIn: CGRect(x: 5, y: 5, width: size - 10, height: size - 10)).fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            let f = UIFont.systemFont(ofSize: 15)
            let s = glyph as NSString
            let sz = s.size(withAttributes: [.font: f])
            s.draw(at: CGPoint(x: (size - sz.width) / 2, y: (size - sz.height) / 2), withAttributes: [.font: f])
        }
    }

    /// Circular avatar marker with a teal ring (TripLayer.buildAvatarMarker).
    static func avatar(photoBase64: String, tag: String) -> UIImage {
        let size: CGFloat = 48, ring: CGFloat = 3
        let teal = UIColor(red: 0, green: 0.788, blue: 0.616, alpha: 1)
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 4, color: UIColor.black.withAlphaComponent(0.33).cgColor)
            teal.setFill(); UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: size - 4, height: size - 4)).fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            let inner = CGRect(x: ring, y: ring, width: size - ring * 2, height: size - ring * 2)
            if let img = Img.decode(photoBase64) {
                ctx.cgContext.saveGState()
                UIBezierPath(ovalIn: inner).addClip()
                img.draw(in: inner)
                ctx.cgContext.restoreGState()
            } else {
                teal.setFill(); UIBezierPath(ovalIn: inner).fill()
                let letter = String(tag.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).first ?? "?").uppercased()
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: inner.width * 0.5), .foregroundColor: UIColor.white]
                let s = letter as NSString
                let sz = s.size(withAttributes: attrs)
                s.draw(at: CGPoint(x: (size - sz.width) / 2, y: (size - sz.height) / 2), withAttributes: attrs)
            }
        }
    }
}
