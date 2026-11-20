import CoreLocation
import Foundation

/// A place near campus that gives out free period products.
///
/// The shipped list only holds spots someone has confirmed: the old web
/// app's pins had conflicting coordinates, missing items and nothing
/// verified, so none of it came across. Add to `product-locations.json` as
/// spots are checked in person — its README describes every field.
struct ProductLocation: Identifiable, Codable, Hashable {
    let id: String
    /// The building, e.g. "Sparks Hall".
    let name: String
    /// Which floor, when the building has more than one, e.g. "2nd floor".
    var floor: String?
    /// How to actually find it, in the words you'd use out loud:
    /// "2nd floor, women's restroom by the elevators".
    var directions: String
    var category: Category
    var address: String?
    var latitude: Double
    var longitude: Double
    /// What's stocked. Empty means nobody has said yet.
    var items: [Item]
    var stockStatus: StockStatus
    /// When someone last checked the spot in person.
    var lastVerified: Date?
    /// When someone last reported on it from the app.
    var lastReported: Date?
    /// Who keeps it filled, e.g. "Student Government" — shown as a credit.
    var refilledBy: String?
    var hours: String?
    var notes: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    enum Category: String, Codable, CaseIterable {
        /// A restroom or commons with a stocked basket.
        case campusRestroom
        /// A campus building pinned without a specific room.
        case campusBuilding
        case clinic
        case partnerStore

        var label: String {
            switch self {
            case .campusRestroom, .campusBuilding: "On campus"
            case .clinic: "Clinic"
            case .partnerStore: "Partner"
            }
        }
    }

    enum Item: String, Codable, CaseIterable {
        case pads
        case tampons
        case liners
        case hairTies
        case painRelief
        /// Used when a spot is known to stock something, but not what.
        case periodProducts

        var label: String {
            switch self {
            case .pads: "Pads"
            case .tampons: "Tampons"
            case .liners: "Liners"
            case .hairTies: "Hair ties"
            case .painRelief: "Pain relief"
            case .periodProducts: "Period products"
            }
        }
    }

    /// How full the spot was the last time anyone said.
    enum StockStatus: String, Codable, CaseIterable {
        case stocked
        case low
        case empty
        case unknown

        var label: String {
            switch self {
            case .stocked: "Stocked"
            case .low: "Running low"
            case .empty: "Empty right now"
            case .unknown: "Not checked lately"
            }
        }
    }

    /// Everything but `id`, `name`, `directions`, `category` and the
    /// coordinates can be left out of the JSON.
    init(
        id: String,
        name: String,
        floor: String? = nil,
        directions: String,
        category: Category,
        address: String? = nil,
        latitude: Double,
        longitude: Double,
        items: [Item] = [],
        stockStatus: StockStatus = .unknown,
        lastVerified: Date? = nil,
        lastReported: Date? = nil,
        refilledBy: String? = nil,
        hours: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.floor = floor
        self.directions = directions
        self.category = category
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.items = items
        self.stockStatus = stockStatus
        self.lastVerified = lastVerified
        self.lastReported = lastReported
        self.refilledBy = refilledBy
        self.hours = hours
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        floor = try container.decodeIfPresent(String.self, forKey: .floor)
        directions = try container.decodeIfPresent(String.self, forKey: .directions) ?? ""
        category = try container.decodeIfPresent(Category.self, forKey: .category) ?? .campusBuilding
        address = try container.decodeIfPresent(String.self, forKey: .address)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        stockStatus = try container.decodeIfPresent(StockStatus.self, forKey: .stockStatus) ?? .unknown
        lastVerified = try container.decodeIfPresent(Date.self, forKey: .lastVerified)
        lastReported = try container.decodeIfPresent(Date.self, forKey: .lastReported)
        refilledBy = try container.decodeIfPresent(String.self, forKey: .refilledBy)
        hours = try container.decodeIfPresent(String.self, forKey: .hours)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

/// Loads the bundled list. It's a local snapshot for now; swapping in
/// Firestore later shouldn't need to touch anything but this type.
enum ProductLocationStore {
    static let all: [ProductLocation] = load()

    /// Everything stocking `item`. A spot that only says "period products"
    /// counts for pads, tampons and liners.
    static func stocking(_ item: ProductLocation.Item, in locations: [ProductLocation] = all) -> [ProductLocation] {
        let coveredByCatchAll: Set<ProductLocation.Item> = [.pads, .tampons, .liners]
        return locations.filter { location in
            location.items.contains(item)
                || (location.items.contains(.periodProducts) && coveredByCatchAll.contains(item))
        }
    }

    /// Nearest first.
    static func sortedByDistance(from origin: CLLocation, in locations: [ProductLocation] = all) -> [ProductLocation] {
        locations.sorted { first, second in
            origin.distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude))
                < origin.distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
        }
    }

    /// Dates in the JSON are plain `yyyy-MM-dd`, so they're readable and
    /// editable by hand.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        decoder.dateDecodingStrategy = .formatted(formatter)
        return decoder
    }()

    private static func load() -> [ProductLocation] {
        guard let url = Bundle.main.url(forResource: "product-locations", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            assertionFailure("product-locations.json is missing from the bundle")
            return []
        }
        do {
            return try decoder.decode([ProductLocation].self, from: data)
        } catch {
            assertionFailure("product-locations.json didn't decode: \(error)")
            return []
        }
    }
}
