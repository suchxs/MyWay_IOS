// AuthComponents.kt — shared auth text field + social button, restyled as SwiftUI.
import SwiftUI

struct AuthTextField: View {
    let title: String
    @Binding var text: String
    var isSecure = false
    var keyboard: UIKeyboardType = .default
    var error: String? = nil
    var enabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if isSecure { SecureField(title, text: $text) }
                else { TextField(title, text: $text).keyboardType(keyboard).textInputAutocapitalization(.never) }
            }
            .disableAutocorrection(true)
            .disabled(!enabled)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).stroke(error == nil ? Color.gray.opacity(0.35) : .red, lineWidth: 1))
            if let error {
                Text(error).font(.footnote).foregroundColor(.red)
            }
        }
    }
}

struct SocialButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var enabled = true

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text("Continue with \(title)").fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.35), lineWidth: 1))
        }
        .disabled(!enabled)
        .foregroundColor(.primary)
    }
}
