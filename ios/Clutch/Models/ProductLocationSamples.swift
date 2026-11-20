#if DEBUG
import Foundation

/// Stand-in spots for previews and screenshots. These are *not* shipped:
/// `product-locations.json` is empty until real, checked-in-person spots
/// are added to it.
extension ProductLocation {
    static let samples: [ProductLocation] = [
        ProductLocation(
            id: "sample-sparks-hall",
            name: "Sparks Hall",
            floor: "2nd floor",
            directions: "2nd floor, women's restroom by the elevators",
            category: .campusRestroom,
            latitude: 33.7538,
            longitude: -84.3855,
            items: [.pads, .tampons],
            stockStatus: .stocked,
            lastVerified: Date(timeIntervalSince1970: 1_789_000_000),
            refilledBy: "Student Government",
            hours: "Mon–Fri, 7am–10pm"
        ),
        ProductLocation(
            id: "sample-library-north",
            name: "University Library North",
            floor: "1st floor",
            directions: "Main lobby, basket on the desk past the turnstiles",
            category: .campusRestroom,
            latitude: 33.7530,
            longitude: -84.3880,
            items: [.pads, .liners],
            stockStatus: .low,
            hours: "Open 24/7"
        ),
        ProductLocation(
            id: "sample-rec-center",
            name: "Recreation Center",
            directions: "Women's locker room, shelf under the mirrors",
            category: .campusRestroom,
            latitude: 33.7575,
            longitude: -84.3850,
            items: [.pads, .tampons, .painRelief],
            stockStatus: .stocked,
            lastVerified: Date(timeIntervalSince1970: 1_789_600_000),
            hours: "Daily, 6am–11pm"
        ),
        ProductLocation(
            id: "sample-student-center-west",
            name: "Student Center West",
            floor: "Ground floor",
            directions: "Just inside the Gilmer Street doors, by the info desk",
            category: .campusBuilding,
            latitude: 33.7535,
            longitude: -84.3853,
            items: [.periodProducts],
            stockStatus: .unknown
        ),
    ]
}
#endif
