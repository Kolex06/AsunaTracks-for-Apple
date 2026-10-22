#if os(macOS)
import SwiftUI
import AppKit

// iOS keyboard and navigation chrome have no Mac equivalent; fields retain native Mac input.
enum MacKeyboardKind { case asciiCapable }
enum MacCapitalization { case never }
enum MacTitleDisplay { case inline }
extension View {
    func keyboardType(_ kind: MacKeyboardKind) -> some View { self }
    func textInputAutocapitalization(_ value: MacCapitalization) -> some View { self }
    func navigationBarTitleDisplayMode(_ value: MacTitleDisplay) -> some View { self }
}

#endif
