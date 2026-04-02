import SwiftUI

struct WorkoutFilesView: View {
    private let primaryOrange = Color(red: 1.0, green: 0.42, blue: 0.21)

    @State private var csvFiles: [URL] = []
    @State private var fileToDelete: URL? = nil
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationView {
            Group {
                if csvFiles.isEmpty {
                    emptyState
                } else {
                    fileList
                }
            }
            .navigationTitle("Workout Files")
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
        }
        .task {
            reload()
        }
        .confirmationDialog(
            "Delete \(fileToDelete?.lastPathComponent ?? "file")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let url = fileToDelete { deleteFile(url) }
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 52))
                .foregroundColor(.gray.opacity(0.4))
            Text("No workout files yet")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gray)
            Text("Complete a workout with your Apple Watch to generate motion CSV files.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var fileList: some View {
        List {
            Section {
                ForEach(csvFiles, id: \.absoluteString) { url in
                    FileRow(url: url)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                fileToDelete = url
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text("\(csvFiles.count) file\(csvFiles.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { reload() }
    }

    // MARK: - Actions

    private func reload() {
        csvFiles = PhoneConnectivityManager.allSavedCSVs()
    }

    private func deleteFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        reload()
    }
}

// MARK: - File Row

private struct FileRow: View {
    let url: URL

    private var fileSize: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int else { return "" }
        let kb = Double(bytes) / 1024
        return kb < 1024
            ? String(format: "%.1f KB", kb)
            : String(format: "%.1f MB", kb / 1024)
    }

    private var modifiedDate: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text.fill")
                .font(.title2)
                .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.21))

            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(modifiedDate)
                    if !fileSize.isEmpty {
                        Text("·")
                        Text(fileSize)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
                    .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.21))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    WorkoutFilesView()
}
