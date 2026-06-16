import SwiftUI

struct FitsSegmentedControl<Option: Identifiable & Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(selection == option ? Color.fitsText : Color.fitsMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selection == option ? Color.fitsElevated : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))
    }
}
