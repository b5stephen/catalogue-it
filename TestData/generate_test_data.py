#!/usr/bin/env python3
"""
generate_test_data.py
Generates sample_catalogue_1000.json — a CatalogueExportFile (v1) with 1000 film items.

Run from the TestData directory or the project root:
    python3 TestData/generate_test_data.py

Output: TestData/sample_catalogue_1000.json
Uses the same deterministic data as TestDataGenerator.swift so both sources
produce comparable datasets.
"""

import json
import os
import uuid
from datetime import datetime, timezone, timedelta

# ---------------------------------------------------------------------------
# Static data (mirrors TestDataGenerator.swift)
# ---------------------------------------------------------------------------

TITLES = [
    "The Grand Illusion", "Breathless", "La Dolce Vita", "8½", "Rashomon",
    "Tokyo Story", "Bicycle Thieves", "The 400 Blows", "Wild Strawberries",
    "Persona", "Scenes from a Marriage", "Amarcord", "The Seventh Seal",
    "M", "Metropolis", "Nosferatu", "Battleship Potemkin", "The Rules of the Game",
    "Hiroshima Mon Amour", "Last Year at Marienbad", "L'Avventura", "Il Posto",
    "Nights of Cabiria", "Rome, Open City", "The General", "Sunrise",
    "Pandora's Box", "The Passion of Joan of Arc", "Earth", "Man with a Movie Camera",
]

DIRECTORS = [
    "Jean Renoir", "Jean-Luc Godard", "Federico Fellini", "Akira Kurosawa",
    "Yasujirō Ozu", "Vittorio De Sica", "François Truffaut", "Ingmar Bergman",
    "Michelangelo Antonioni", "Roberto Rossellini", "Buster Keaton",
    "F.W. Murnau", "Sergei Eisenstein", "Alain Resnais", "Ermanno Olmi",
    "Fritz Lang", "Luis Buñuel", "Carl Theodor Dreyer", "Dziga Vertov",
]

NOTES_SAMPLES = [
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

# ---------------------------------------------------------------------------
# Field definition UUIDs — fixed so the file is reproducible
# ---------------------------------------------------------------------------

TITLE_FIELD_ID    = "10000000-0000-0000-0000-000000000001"
DIRECTOR_FIELD_ID = "10000000-0000-0000-0000-000000000002"
YEAR_FIELD_ID     = "10000000-0000-0000-0000-000000000003"
RATING_FIELD_ID   = "10000000-0000-0000-0000-000000000004"
WATCHED_FIELD_ID  = "10000000-0000-0000-0000-000000000005"
DATE_WATCHED_FIELD_ID = "10000000-0000-0000-0000-000000000006"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

BASE_DATE = datetime(2020, 1, 1, 0, 0, 0, tzinfo=timezone.utc)

def iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def add_days(base: datetime, days: int) -> datetime:
    return base + timedelta(days=days)

# ---------------------------------------------------------------------------
# Generate items
# ---------------------------------------------------------------------------

def make_item(index: int) -> dict:
    title_index    = index % len(TITLES)
    director_index = (index * 3) % len(DIRECTORS)
    year           = 1950 + (index * 7) % 76          # 1950–2025
    rating         = max(1.0, (index * 13) % 21 * 0.5) # 1.0–10.0, step 0.5
    watched        = (index % 5) != 0                  # ~80% watched
    is_wishlist    = (index % 5) == 1                  # ~20% wishlist
    has_rating     = (index % 10) != 0                 # ~10% missing rating
    has_notes      = (index % 7) == 0                  # ~14% have notes

    title_suffix = f" ({index // len(TITLES) + 1})" if index >= len(TITLES) else ""
    title = TITLES[title_index] + title_suffix
    notes = NOTES_SAMPLES[index % len(NOTES_SAMPLES)] if has_notes else None

    created_date = add_days(BASE_DATE, (index * 3) % (365 * 3))

    field_values = [
        {
            "fieldDefinitionID": TITLE_FIELD_ID,
            "fieldType": "Text",
            "textValue": title,
        },
        {
            "fieldDefinitionID": DIRECTOR_FIELD_ID,
            "fieldType": "Text",
            "textValue": DIRECTORS[director_index],
        },
        {
            "fieldDefinitionID": YEAR_FIELD_ID,
            "fieldType": "Number",
            "numberValue": float(year),
        },
    ]

    if has_rating:
        field_values.append({
            "fieldDefinitionID": RATING_FIELD_ID,
            "fieldType": "Number",
            "numberValue": round(rating, 1),
        })

    field_values.append({
        "fieldDefinitionID": WATCHED_FIELD_ID,
        "fieldType": "Yes/No",
        "boolValue": watched,
    })

    if watched:
        watched_day_offset = (index * 11) % (365 * 3)
        watched_date = add_days(BASE_DATE, watched_day_offset)
        field_values.append({
            "fieldDefinitionID": DATE_WATCHED_FIELD_ID,
            "fieldType": "Date",
            "dateValue": iso(watched_date),
        })

    item: dict = {
        "createdDate": iso(created_date),
        "isWishlist": is_wishlist,
        "fieldValues": field_values,
        "photos": [],
    }
    if notes is not None:
        item["notes"] = notes

    return item

# ---------------------------------------------------------------------------
# Assemble export file
# ---------------------------------------------------------------------------

def generate(item_count: int = 1000) -> dict:
    return {
        "version": 1,
        "exportedAt": iso(datetime.now(timezone.utc)),
        "catalogues": [
            {
                "name": "Film Collection (Test Data)",
                "iconName": "film",
                "colorHex": "#8B5CF6",
                "createdDate": iso(BASE_DATE),
                "priority": 0,
                "sortFieldKey": TITLE_FIELD_ID,
                "sortDirection": "asc",
                "fieldDefinitions": [
                    {
                        "fieldID": TITLE_FIELD_ID,
                        "name": "Title",
                        "fieldType": "Text",
                        "priority": 0,
                    },
                    {
                        "fieldID": DIRECTOR_FIELD_ID,
                        "name": "Director",
                        "fieldType": "Text",
                        "priority": 1,
                    },
                    {
                        "fieldID": YEAR_FIELD_ID,
                        "name": "Year",
                        "fieldType": "Number",
                        "priority": 2,
                        "fieldOptions": {"number": {"_0": {"format": "Number", "precision": 0}}},
                    },
                    {
                        "fieldID": RATING_FIELD_ID,
                        "name": "Rating",
                        "fieldType": "Number",
                        "priority": 3,
                        "fieldOptions": {"number": {"_0": {"format": "Number", "precision": 1}}},
                    },
                    {
                        "fieldID": WATCHED_FIELD_ID,
                        "name": "Watched",
                        "fieldType": "Yes/No",
                        "priority": 4,
                    },
                    {
                        "fieldID": DATE_WATCHED_FIELD_ID,
                        "name": "Date Watched",
                        "fieldType": "Date",
                        "priority": 5,
                    },
                ],
                "items": [make_item(i) for i in range(item_count)],
            }
        ],
    }

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, "sample_catalogue_1000.json")

    data = generate(item_count=1000)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    item_count = len(data["catalogues"][0]["items"])
    size_kb = os.path.getsize(output_path) // 1024
    print(f"Written {output_path}")
    print(f"  {item_count} items, {size_kb} KB")
