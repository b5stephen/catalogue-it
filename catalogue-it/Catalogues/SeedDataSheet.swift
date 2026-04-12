//
//  SeedDataSheet.swift
//  catalogue-it

#if DEBUG
import SwiftUI

struct SeedDataSheet: View {
    var onGenerate: (Int, Bool, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var itemCount: Double = 500
    @State private var includesPhotos: Bool = false
    @State private var catalogueName: String = ""

    private func computedName(count: Double, photos: Bool) -> String {
        let suffix = photos ? " + Photos" : ""
        return "Film Collection – \(Int(count))\(suffix) (Test Data)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Catalogue Name", text: $catalogueName)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Item Count")
                            Spacer()
                            Text("\(Int(itemCount))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $itemCount, in: 100...5000, step: 100)
                    }
                    .padding(.vertical, 4)

                    Toggle("Include Photos", isOn: $includesPhotos)
                }

                if itemCount > 1000 {
                    Section {
                        Label(
                            "Generating over 1,000 items may take a long time.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.yellow)
                        .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Load Test Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        onGenerate(Int(itemCount), includesPhotos, catalogueName)
                        dismiss()
                    }
                    .disabled(catalogueName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                catalogueName = computedName(count: itemCount, photos: includesPhotos)
            }
            .onChange(of: itemCount) { oldCount, newCount in
                // Only auto-update the name if it still matches the previous computed default,
                // meaning the user hasn't typed a custom name.
                if catalogueName == computedName(count: oldCount, photos: includesPhotos) {
                    catalogueName = computedName(count: newCount, photos: includesPhotos)
                }
            }
            .onChange(of: includesPhotos) { oldPhotos, newPhotos in
                if catalogueName == computedName(count: itemCount, photos: oldPhotos) {
                    catalogueName = computedName(count: itemCount, photos: newPhotos)
                }
            }
        }
    }
}

#Preview {
    SeedDataSheet { count, photos, name in
        print("Generate \(count) items, photos: \(photos), name: \(name)")
    }
}
#endif
