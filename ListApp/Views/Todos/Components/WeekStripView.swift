import SwiftUI

struct WeekStripView: View {
    let startDate: Date
    let counts: [Int]   // length 7
    @Binding var selectedIndex: Int

    private let cal = Calendar.current

    private func date(for i: Int) -> Date {
        cal.date(byAdding: .day, value: i, to: startDate) ?? startDate
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let d = date(for: i)
                let selected = i == selectedIndex
                let n = i < counts.count ? counts[i] : 0
                Button {
                    withAnimation { selectedIndex = i }
                } label: {
                    VStack(spacing: 4) {
                        Text(weekday(d))
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(0.6)
                        Text("\(day(d))")
                            .font(.system(size: 18, weight: .semibold))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(selected ? Color.white : (n > 0 ? TodoToken.blue : Color.clear))
                            .frame(width: CGFloat(max(6, n * 3)), height: 4)
                            .opacity(0.8)
                    }
                    .foregroundStyle(selected ? Color.white : TodoToken.fg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selected ? TodoToken.blue : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? Color.clear : TodoToken.lineS, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: d).uppercased()
    }
    private func day(_ d: Date) -> Int { cal.component(.day, from: d) }
}
