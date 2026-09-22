# product-locations.json

Every spot on the Request screen — "free products near you" — comes from
this file. It ships **empty on purpose**: the old Next.js app's pins had
conflicting coordinates (two buildings sharing one point), no items on half
of them, and nothing verified by a person. Add spots here as you check them
yourself.

The app reads it once at launch, so a spot appears as soon as it's in the
list. Dates are plain `yyyy-MM-dd` so they stay easy to edit by hand.

## Fields

| Field | Required | What it is |
|---|---|---|
| `id` | yes | Stable slug, e.g. `sparks-hall-2nd-floor`. Reports are filed against it, so don't reuse or rename one. |
| `name` | yes | The building, as she'd say it: "Sparks Hall". |
| `floor` | no | "2nd floor". Leave out for a one-floor spot. |
| `directions` | yes | How to actually find it, in plain words: "2nd floor, women's restroom by the elevators". This is the line under the name. |
| `category` | yes | `campusRestroom`, `campusBuilding`, `clinic` or `partnerStore`. |
| `address` | no | Street address, for spots off campus. |
| `latitude` / `longitude` | yes | Decimal degrees. Stand at the door and take the reading — building-centre coordinates send people to the wrong entrance. |
| `items` | no | Any of `pads`, `tampons`, `liners`, `hairTies`, `painRelief`. Use `periodProducts` only when you know it's stocked but not with what. Empty means nobody has said yet. |
| `stockStatus` | no | `stocked`, `low`, `empty` or `unknown` (the default). |
| `lastVerified` | no | `yyyy-MM-dd` you last saw it stocked in person. Blank reads as "not checked lately". |
| `lastReported` | no | `yyyy-MM-dd` of the last report from the app. "Report empty" is stored on the device for now, so this stays a manual field until there's a backend. |
| `refilledBy` | no | Who keeps it filled, e.g. "Student Government". Shown as a credit. |
| `hours` | no | When the building is open, e.g. "Mon–Fri, 7am–10pm". |
| `notes` | no | Anything else worth saying: "basket is under the sink". |

## Example

```json
[
  {
    "id": "sparks-hall-2nd-floor",
    "name": "Sparks Hall",
    "floor": "2nd floor",
    "directions": "2nd floor, women's restroom by the elevators",
    "category": "campusRestroom",
    "latitude": 33.75380,
    "longitude": -84.38550,
    "items": ["pads", "tampons"],
    "stockStatus": "stocked",
    "lastVerified": "2026-09-20",
    "refilledBy": "Student Government",
    "hours": "Mon–Fri, 7am–10pm",
    "notes": "Basket sits on the shelf under the mirror."
  }
]
```
