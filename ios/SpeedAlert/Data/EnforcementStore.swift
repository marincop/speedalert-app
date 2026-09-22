import Foundation
import CoreLocation

/// Loads the bundled offline dataset and answers proximity queries.
///
/// Primary source is a **binary property list** (`app_data.plist`) because
/// Foundation's JSON parser rejected our (otherwise valid) UTF-8 JSON on
/// iOS 26. Falls back to `app_data.json`. Never crashes: records `loadError`.
final class EnforcementStore: ObservableObject {
    @Published private(set) var itemCount: Int = 0
    @Published private(set) var builtAt: String?
    @Published private(set) var loadError: String?
    @Published private(set) var resourceFound = false

    private var items: [EnforcementItem] = []
    private var grid: [Int64: [Int]] = [:]          // cellKey -> indices
    private let cell = 0.02                          // ~2.2 km cells
    private let metersPerDegLat = 111_320.0

    init(bundle: Bundle = .main) { load(bundle: bundle) }

    func load(bundle: Bundle) {
        // 1) binary plist (primary)
        if let url = bundle.url(forResource: "app_data", withExtension: "plist"),
           let data = try? Data(contentsOf: url) {
            resourceFound = true
            if decode(data, usingPlist: true, name: url.lastPathComponent) { return }
        }
        // 2) JSON (fallback)
        if let url = bundle.url(forResource: "app_data", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            resourceFound = true
            if decode(data, usingPlist: false, name: url.lastPathComponent) { return }
        }
        if !resourceFound {
            loadError = "app_data not in bundle"
            NSLog("[SpeedAlert] MISSING app_data; json=%@",
                  bundle.paths(forResourcesOfType: "json", inDirectory: nil).description)
        }
    }

    private func decode(_ data: Data, usingPlist: Bool, name: String) -> Bool {
        do {
            let raw: RawAppData
            if usingPlist {
                raw = try PropertyListDecoder().decode(RawAppData.self, from: data)
            } else {
                raw = try JSONDecoder().decode(RawAppData.self, from: data)
            }
            builtAt = raw.builtAt
            var all = raw.cameras.map { $0.toItem() }
            all.append(contentsOf: raw.sections.map { $0.toItem() })
            all.append(contentsOf: raw.accidents.compactMap { $0.toItem() })
            items = all
            buildIndex()
            itemCount = items.count
            loadError = nil
            NSLog("[SpeedAlert] loaded %d items from %@ (cameras=%d sections=%d accidents=%d)",
                  itemCount, name, raw.cameras.count, raw.sections.count, raw.accidents.count)
            return true
        } catch {
            let d = EnforcementStore.describe(error)
            loadError = "(\(name)) " + d
            NSLog("[SpeedAlert] %@ decode FAILED: %@ (count=%d)", name, d, data.count)
            return false
        }
    }

    /// Detailed, human-readable description of a decoding error (incl. codingPath).
    static func describe(_ error: Error) -> String {
        guard let de = error as? DecodingError else { return "\(error)" }
        func joined(_ path: [CodingKey]) -> String {
            return path.map { $0.stringValue }.joined(separator: ".")
        }
        switch de {
        case .dataCorrupted(let ctx):          return "dataCorrupted @[\(joined(ctx.codingPath))] :: \(ctx.debugDescription)"
        case .keyNotFound(let key, let ctx):   return "keyNotFound(\(key.stringValue)) @[\(joined(ctx.codingPath))]"
        case .typeMismatch(let type, let ctx): return "typeMismatch(\(type)) @[\(joined(ctx.codingPath))]"
        case .valueNotFound(let type, let ctx): return "valueNotFound(\(type)) @[\(joined(ctx.codingPath))]"
        @unknown default:                      return "decoding error \(de)"
        }
    }

    private func cellKey(_ latCell: Int, _ lonCell: Int) -> Int64 {
        (Int64(latCell) << 32) ^ Int64(UInt32(bitPattern: Int32(lonCell)))
    }

    private func buildIndex() {
        grid.removeAll(keepingCapacity: true)
        for (i, it) in items.enumerated() {
            let key = cellKey(Int(floor(it.lat / cell)), Int(floor(it.lon / cell)))
            grid[key, default: []].append(i)
        }
    }

    /// Items within `radius` metres of `coord`, nearest first.
    func nearby(_ coord: CLLocationCoordinate2D,
                radius: CLLocationDistance,
                kinds: Set<EnforcementKind> = Set(EnforcementKind.allCases)) -> [NearbyHit] {
        let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let latSpan = Int(ceil(radius / (cell * metersPerDegLat))) + 1
        let lonScale = max(cos(coord.latitude * .pi / 180), 0.1)
        let lonSpan = Int(ceil(radius / (cell * metersPerDegLat * lonScale))) + 1
        let latCell = Int(floor(coord.latitude / cell))
        let lonCell = Int(floor(coord.longitude / cell))

        var hits: [NearbyHit] = []
        var seen = Set<Int>()
        for dy in -latSpan...latSpan {
            for dx in -lonSpan...lonSpan {
                guard let idxs = grid[cellKey(latCell + dy, lonCell + dx)] else { continue }
                for i in idxs where seen.insert(i).inserted {
                    let it = items[i]
                    guard kinds.contains(it.kind) else { continue }
                    let d = origin.distance(from: CLLocation(latitude: it.lat, longitude: it.lon))
                    guard d <= radius else { continue }
                    hits.append(NearbyHit(item: it, distance: d,
                                          bearing: EnforcementStore.bearing(from: coord, to: it.coordinate)))
                }
            }
        }
        hits.sort { $0.distance < $1.distance }
        return hits
    }

    /// Initial bearing from one coordinate to another (degrees, 0 = north).
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180
        let dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
