import Foundation
import CoreLocation

/// What kind of enforcement / hazard a point represents.
enum EnforcementKind: String, Codable, CaseIterable {
    case fixedSpeed        = "fixed_speed"
    case highwaySpeed      = "highway_speed"
    case intervalSpeed     = "interval_speed"
    case techIntersection  = "tech_intersection"
    case techOther         = "tech_other"
    case accidentSegment   = "accident_segment"

    var displayName: String {
        switch self {
        case .fixedSpeed:       return "固定式測速"
        case .highwaySpeed:     return "國道測速"
        case .intervalSpeed:    return "區間測速"
        case .techIntersection: return "路口科技執法"
        case .techOther:        return "科技執法"
        case .accidentSegment:  return "易肇事路段"
        }
    }

    /// Noun used in the spoken alert, e.g. "前方300公尺測速照相".
    var spokenNoun: String {
        switch self {
        case .fixedSpeed, .highwaySpeed: return "測速照相"
        case .intervalSpeed:            return "區間測速"
        case .techIntersection, .techOther: return "科技執法"
        case .accidentSegment:          return "易肇事路段"
        }
    }
}

/// A single enforcement/hazard point the app can alert on.
struct EnforcementItem: Identifiable, Equatable {
    let id: Int
    let kind: EnforcementKind
    let lat: Double
    let lon: Double
    let limit: Int?
    let dir: String?
    let addr: String?
    let city: String?
    let endLat: Double?
    let endLon: Double?

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    /// Human label for lists / UI.
    var label: String { addr ?? city ?? kind.displayName }
}

/// A query result: item + how far away it is (metres) + bearing from the user.
struct NearbyHit: Identifiable {
    let item: EnforcementItem
    let distance: CLLocationDistance
    let bearing: Double
    var id: Int { item.id }
}

// MARK: - Decoding layer for data/app_data.json (produced by export_app_data.py)

struct RawAppData: Codable {
    let schema: Int
    let builtAt: String?
    let cameras: [RawCamera]
    let sections: [RawSection]
    let accidents: [RawAccident]

    enum CodingKeys: String, CodingKey {
        case schema, cameras, sections, accidents
        case builtAt = "built_at"
    }
}

struct RawCamera: Codable {
    let id: Int
    let kind: EnforcementKind
    let lat: Double
    let lon: Double
    let limit: Int?
    let dir: String?
    let addr: String?
    let city: String?

    func toItem() -> EnforcementItem {
        EnforcementItem(id: id, kind: kind, lat: lat, lon: lon, limit: limit,
                        dir: dir, addr: addr, city: city, endLat: nil, endLon: nil)
    }
}

struct RawSection: Codable {
    let id: Int
    let name: String?
    let city: String?
    let limit: Int?
    let lat: Double
    let lon: Double
    let endLat: Double?
    let endLon: Double?

    func toItem() -> EnforcementItem {
        // section ids may collide with camera ids -> offset high bucket
        EnforcementItem(id: 1_000_000 + id, kind: .intervalSpeed, lat: lat, lon: lon,
                        limit: limit, dir: nil, addr: name, city: city,
                        endLat: endLat, endLon: endLon)
    }
}

struct RawAccident: Codable {
    let id: Int
    let name: String?
    let city: String?
    let lat: Double?
    let lon: Double?
    let severity: String?

    func toItem() -> EnforcementItem? {
        guard let lat, let lon else { return nil }
        return EnforcementItem(id: 2_000_000 + id, kind: .accidentSegment, lat: lat, lon: lon,
                               limit: nil, dir: nil, addr: name, city: city,
                               endLat: nil, endLon: nil)
    }
}
