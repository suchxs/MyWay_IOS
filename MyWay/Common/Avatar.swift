// Avatar.kt — base64 image encode/decode + a circular avatar. Android stored small JPEGs as base64
// inline in Firestore docs; we keep the exact same wire format so both apps interop.
import SwiftUI
import UIKit

enum Img {
    /// Downscale + JPEG-compress to a small base64 string (matches Android's inline-avatar size budget).
    static func encode(_ image: UIImage, maxDimension: CGFloat = 256, quality: CGFloat = 0.7) -> String {
        let scaled = resize(image, maxDimension: maxDimension)
        return scaled.jpegData(compressionQuality: quality)?.base64EncodedString() ?? ""
    }

    static func decode(_ base64: String) -> UIImage? {
        guard !base64.isEmpty, let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        if scale >= 1 { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

/// Circular avatar from a base64 photo, falling back to a teal initial (AvatarCircle in Avatar.kt).
struct AvatarCircle: View {
    let photoBase64: String
    let tag: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let ui = Img.decode(photoBase64) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                ZStack {
                    Brand.teal
                    Text(initial).font(.system(size: size * 0.45, weight: .bold)).foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initial: String {
        let t = tag.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        return String(t.first ?? "?").uppercased()
    }
}
