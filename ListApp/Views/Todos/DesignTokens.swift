import SwiftUI

// Design tokens ported from the wireframe bundle's wire-primitives.jsx.
// Dark-first palette, mapped to semantic SwiftUI colors where possible.
enum TodoToken {
    static let bg        = Color.black
    static let card      = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let card2     = Color(red: 0.078, green: 0.078, blue: 0.086)
    static let line      = Color(red: 0.149, green: 0.149, blue: 0.165)
    static let lineS     = Color(red: 0.102, green: 0.102, blue: 0.114)
    static let fg        = Color(red: 0.902, green: 0.902, blue: 0.910)
    static let mute      = Color(red: 0.541, green: 0.541, blue: 0.565)
    static let dim       = Color(red: 0.333, green: 0.333, blue: 0.357)
    static let blue      = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let red       = Color(red: 1.0,   green: 0.271, blue: 0.227)
    static let green     = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let orange    = Color(red: 1.0,   green: 0.624, blue: 0.039)
    static let purple    = Color(red: 0.749, green: 0.353, blue: 0.949)
    static let fill      = Color(white: 0.47).opacity(0.22)
    static let fillS     = Color(white: 0.47).opacity(0.12)
}
