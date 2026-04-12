//
//  TestDataGenerator.swift
//  catalogue-it
//

#if DEBUG
import Foundation
import SwiftData

// MARK: - Test Data Generator (Debug Only)

/// Seeds a large catalogue into SwiftData for performance testing.
/// Only compiled in Debug builds — completely absent from release / App Store builds.
enum TestDataGenerator {

    static let catalogueName = "Film Collection (Test Data)"

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

    /// Seeds a "Film Collection" catalogue with `itemCount` items directly into SwiftData.
    ///
    /// - Parameters:
    ///   - context: The SwiftData context to insert into.
    ///   - itemCount: Number of items to generate (default: 1000).
    ///   - priorityOffset: Added to the catalogue's priority so it appends after existing catalogues.
    ///   - onProgress: Called after each item is processed with (completedItems, totalItems).
    /// - Returns: The newly created `Catalogue`.
    @MainActor
    static func seed(
        into context: ModelContext,
        itemCount: Int = 1000,
        priorityOffset: Int = 0,
        onProgress: ((Int, Int) -> Void)? = nil
    ) -> Catalogue {
        let catalogue = Catalogue(
            name: catalogueName,
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

            onProgress?(index + 1, itemCount)
        }

        return catalogue
    }
}
#endif
