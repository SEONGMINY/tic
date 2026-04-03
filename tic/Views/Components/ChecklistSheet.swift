import SwiftUI

struct ChecklistSheet: View {
    var reminders: [TicItem]
    var onToggle: (TicItem) -> Void
    var onEdit: ((TicItem) -> Void)?
    var onDelete: ((TicItem) -> Void)?

    var body: some View {
        NavigationStack {
            List {
                ForEach(reminders) { item in
                    Button {
                        onToggle(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isCompleted ? .green : .secondary)
                                .font(.title3)

                            Text(item.title)
                                .strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        }
                    }
                    .contextMenu {
                        Button("수정") { onEdit?(item) }
                        Button("삭제", role: .destructive) { onDelete?(item) }
                        if !item.isCompleted {
                            Button("완료") { onToggle(item) }
                        }
                    }
                }
            }
            .navigationTitle("체크리스트")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
