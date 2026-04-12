//
//  TestDataGenerator.swift
//  catalogue-it

#if DEBUG
import Foundation
import CoreGraphics
import ImageIO
import SwiftData

// MARK: - Test Data Generator (Debug Only)

/// Seeds a large catalogue into SwiftData for performance testing.
/// Only compiled in Debug builds — completely absent from release / App Store builds.
enum TestDataGenerator {

    // MARK: - Dataset

    enum TestDataset: CaseIterable {
        case items100, items500, items1k, items10k
        case items100WithPhotos, items500WithPhotos, items1kWithPhotos, items10kWithPhotos

        var displayName: String {
            switch self {
            case .items100:             return "100 Items"
            case .items500:             return "500 Items"
            case .items1k:              return "1k Items"
            case .items10k:             return "10k Items"
            case .items100WithPhotos:   return "100 Items + Photos"
            case .items500WithPhotos:   return "500 Items + Photos"
            case .items1kWithPhotos:    return "1k Items + Photos"
            case .items10kWithPhotos:   return "10k Items + Photos"
            }
        }

        var itemCount: Int {
            switch self {
            case .items100, .items100WithPhotos:  return 100
            case .items500, .items500WithPhotos:  return 500
            case .items1k, .items1kWithPhotos:    return 1_000
            case .items10k, .items10kWithPhotos:  return 10_000
            }
        }

        var includesPhotos: Bool {
            switch self {
            case .items100WithPhotos, .items500WithPhotos,
                 .items1kWithPhotos, .items10kWithPhotos: return true
            default: return false
            }
        }

        var catalogueName: String {
            switch self {
            case .items100:             return "Film Collection – 100 (Test Data)"
            case .items500:             return "Film Collection – 500 (Test Data)"
            case .items1k:              return "Film Collection – 1k (Test Data)"
            case .items10k:             return "Film Collection – 10k (Test Data)"
            case .items100WithPhotos:   return "Film Collection – 100 + Photos (Test Data)"
            case .items500WithPhotos:   return "Film Collection – 500 + Photos (Test Data)"
            case .items1kWithPhotos:    return "Film Collection – 1k + Photos (Test Data)"
            case .items10kWithPhotos:   return "Film Collection – 10k + Photos (Test Data)"
            }
        }
    }

    // MARK: - Source Data

    private static let titles: [String] = [
        "The Grand Illusion", "Breathless", "La Dolce Vita", "8½", "Rashomon",
        "Tokyo Story", "Bicycle Thieves", "The 400 Blows", "Wild Strawberries",
        "Persona", "Scenes from a Marriage", "Amarcord", "The Seventh Seal",
        "M", "Metropolis", "Nosferatu", "Battleship Potemkin", "The Rules of the Game",
        "Hiroshima Mon Amour", "Last Year at Marienbad", "L'Avventura", "Il Posto",
        "Nights of Cabiria", "Rome, Open City", "The General", "Sunrise",
        "Pandora's Box", "The Passion of Joan of Arc", "Earth", "Man with a Movie Camera"
    ]

    private static let directors: [String] = [
        "Jean Renoir", "Jean-Luc Godard", "Federico Fellini", "Akira Kurosawa",
        "Yasujirō Ozu", "Vittorio De Sica", "François Truffaut", "Ingmar Bergman",
        "Michelangelo Antonioni", "Roberto Rossellini", "Buster Keaton",
        "F.W. Murnau", "Sergei Eisenstein", "Alain Resnais", "Ermanno Olmi",
        "Fritz Lang", "Luis Buñuel", "Carl Theodor Dreyer", "Dziga Vertov"
    ]

    private static let notesSamples: [String] = [
        "One of my all-time favourites.",
        "Slow burn but worth it.",
        "Need to rewatch this.",
        "Borrowed from the library.",
        "Watched with friends.",
        "Fell asleep the first time.",
        "Better than expected.",
        "A genuine masterpiece.",
        "Overrated in my opinion.",
        "Changed how I think about cinema.",
        "Beautiful cinematography.",
        "Brilliant performances throughout.",
        "Hard to find a good copy.",
        "Recommended by a friend.",
        "Found on a random streaming service.",
    ]

    // MARK: - Seed

    /// Seeds a "Film Collection" catalogue into SwiftData for the given dataset variant.
    ///
    /// - Parameters:
    ///   - context: The SwiftData context to insert into.
    ///   - dataset: Which dataset variant to generate (size + photos).
    ///   - priorityOffset: Added to the catalogue's priority so it appends after existing catalogues.
    ///   - onProgress: Called after each item is processed with (completedItems, totalItems).
    /// - Returns: The newly created `Catalogue`.
    @MainActor
    static func seed(
        into context: ModelContext,
        dataset: TestDataset = .items1k,
        priorityOffset: Int = 0,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async -> Catalogue {
        let itemCount = dataset.itemCount

        let catalogue = Catalogue(
            name: dataset.catalogueName,
            iconName: "film",
            colorHex: "#8B5CF6",
            priority: priorityOffset
        )
        context.insert(catalogue)

        // Field definitions — all 4 field types represented
        let titleDef = FieldDefinition(name: "Title", fieldType: .text, priority: 0)
        let directorDef = FieldDefinition(name: "Director", fieldType: .text, priority: 1)
        let yearDef = FieldDefinition(name: "Year", fieldType: .number, priority: 2)
        yearDef.fieldOptions = .number(NumberOptions(format: .number, precision: 0))
        let ratingDef = FieldDefinition(name: "Rating", fieldType: .number, priority: 3)
        ratingDef.fieldOptions = .number(NumberOptions(format: .number, precision: 1))
        let watchedDef = FieldDefinition(name: "Watched", fieldType: .boolean, priority: 4)
        let dateWatchedDef = FieldDefinition(name: "Date Watched", fieldType: .date, priority: 5)

        let allDefs = [titleDef, directorDef, yearDef, ratingDef, watchedDef, dateWatchedDef]
        for def in allDefs {
            def.catalogue = catalogue
            context.insert(def)
        }

        let baseDate = ISO8601DateFormatter().date(from: "2020-01-01T00:00:00Z") ?? Date.now
        let calendar = Calendar.current

        for index in 0..<itemCount {
            // Deterministic variety — same output on every seed call
            let titleIndex = index % titles.count
            let directorIndex = (index * 3) % directors.count
            let year = Double(1950 + (index * 7) % 76)                     // 1950–2025
            let rating = max(1.0, Double((index * 13) % 21) * 0.5)         // 1.0–10.0, step 0.5
            let watched = index % 5 != 0                                    // ~80% watched
            let isWishlist = index % 5 == 1                                 // ~20% wishlist
            let hasRating = index % 10 != 0                                 // ~10% missing rating
            let hasNotes = index % 7 == 0                                   // ~14% have notes

            // Disambiguate titles on repeat cycles: "Rashomon", "Rashomon (2)", …
            let titleSuffix = index >= titles.count ? " (\(index / titles.count + 1))" : ""
            let title = titles[titleIndex] + titleSuffix
            let notes: String? = hasNotes ? notesSamples[index % notesSamples.count] : nil

            let item = CatalogueItem(isWishlist: isWishlist, notes: notes)
            let createdDayOffset = (index * 3) % (365 * 3)
            item.createdDate = calendar.date(byAdding: .day, value: createdDayOffset, to: baseDate) ?? baseDate
            item.catalogue = catalogue
            context.insert(item)

            var fieldValues: [FieldValue] = []

            let titleFV = FieldValue(fieldDefinition: titleDef, fieldType: .text)
            titleFV.textValue = title
            titleFV.sortKey = SortKeyEncoder.sortKey(for: titleFV)
            titleFV.item = item
            context.insert(titleFV)
            fieldValues.append(titleFV)

            let directorFV = FieldValue(fieldDefinition: directorDef, fieldType: .text)
            directorFV.textValue = directors[directorIndex]
            directorFV.sortKey = SortKeyEncoder.sortKey(for: directorFV)
            directorFV.item = item
            context.insert(directorFV)
            fieldValues.append(directorFV)

            let yearFV = FieldValue(fieldDefinition: yearDef, fieldType: .number)
            yearFV.numberValue = year
            yearFV.sortKey = SortKeyEncoder.sortKey(for: yearFV)
            yearFV.item = item
            context.insert(yearFV)
            fieldValues.append(yearFV)

            if hasRating {
                let ratingFV = FieldValue(fieldDefinition: ratingDef, fieldType: .number)
                ratingFV.numberValue = rating
                ratingFV.sortKey = SortKeyEncoder.sortKey(for: ratingFV)
                ratingFV.item = item
                context.insert(ratingFV)
                fieldValues.append(ratingFV)
            }

            let watchedFV = FieldValue(fieldDefinition: watchedDef, fieldType: .boolean)
            watchedFV.boolValue = watched
            watchedFV.sortKey = SortKeyEncoder.sortKey(for: watchedFV)
            watchedFV.item = item
            context.insert(watchedFV)
            fieldValues.append(watchedFV)

            if watched {
                let watchedDayOffset = (index * 11) % (365 * 3)
                let watchedDate = calendar.date(byAdding: .day, value: watchedDayOffset, to: baseDate)
                let dateWatchedFV = FieldValue(fieldDefinition: dateWatchedDef, fieldType: .date)
                dateWatchedFV.dateValue = watchedDate
                dateWatchedFV.sortKey = SortKeyEncoder.sortKey(for: dateWatchedFV)
                dateWatchedFV.item = item
                context.insert(dateWatchedFV)
                fieldValues.append(dateWatchedFV)
            }

            item.searchText = SearchTextBuilder.build(from: fieldValues)

            if dataset.includesPhotos, let photoData = makePhotoData(index: index) {
                let thumbnail = makeThumbnailData(from: photoData)
                let photo = ItemPhoto(imageData: photoData, thumbnailData: thumbnail, priority: 0)
                photo.item = item
                context.insert(photo)
            }

            onProgress?(index + 1, itemCount)
            if index % 100 == 99 {
                await Task.yield()
            }
        }

        return catalogue
    }

    // MARK: - Photo Generation

    /// Generates a deterministic 400×300 JPEG with a colored background and diagonal stripe.
    /// Uses CoreGraphics only — no UIKit/AppKit dependency.
    private static func makePhotoData(index: Int) -> Data? {
        let width = 400, height = 300
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // Deterministic hue cycling across 12 colours
        let hue = CGFloat(index % 12) / 12.0
        let (r, g, b) = hsvToRGB(h: hue, s: 0.55, v: 0.80)

        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Diagonal stripe for visual texture
        ctx.setFillColor(red: r * 0.85, green: g * 0.85, blue: b * 0.85, alpha: 1)
        let stripe = CGMutablePath()
        stripe.move(to: CGPoint(x: 0, y: 80))
        stripe.addLine(to: CGPoint(x: 220, y: CGFloat(height)))
        stripe.addLine(to: CGPoint(x: 300, y: CGFloat(height)))
        stripe.addLine(to: CGPoint(x: 80, y: 0))
        stripe.addLine(to: CGPoint(x: 0, y: 0))
        ctx.addPath(stripe)
        ctx.fillPath()

        guard let cgImage = ctx.makeImage() else { return nil }
        let mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0)!
        guard let dest = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    private static func hsvToRGB(h: CGFloat, s: CGFloat, v: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let i = Int(h * 6)
        let f = h * 6 - CGFloat(i)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
#endif
