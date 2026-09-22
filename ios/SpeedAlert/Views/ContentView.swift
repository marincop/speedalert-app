import SwiftUI

// MARK: - Kind styling

extension EnforcementKind {
    var symbol: String {
        switch self {
        case .fixedSpeed:       return "camera.fill"
        case .highwaySpeed:     return "road.lanes"
        case .intervalSpeed:    return "timer"
        case .techIntersection: return "trafficlight"
        case .techOther:        return "camera.viewfinder"
        case .accidentSegment:  return "exclamationmark.triangle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .fixedSpeed, .highwaySpeed: return .red
        case .intervalSpeed:             return .orange
        case .techIntersection, .techOther: return .blue
        case .accidentSegment:           return .yellow
        }
    }
}

// MARK: - Speed limit sign (white circle / red ring / black number)

struct SpeedLimitBadge: View {
    let limit: Int
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(.red, lineWidth: max(3, size * 0.11))
            Text("\(limit)")
                .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                .foregroundStyle(.black)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Content

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    topBar
                    speedHero
                    if let next = model.nearest.first { nextAlertCard(next) }
                    driveButton
                    if !model.lastAlert.isEmpty { lastSpoken }
                    nearbySection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
    }

    private var background: some View {
        LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.15),
                                Color(red: 0.02, green: 0.02, blue: 0.05)],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: pieces

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("測速提醒").font(.title3.bold())
                Text("全台測速 · 科技執法 · 肇事路段").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            dataChip
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .padding(9)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .foregroundStyle(.white)
        }
    }

    private var dataChip: some View {
        let store = model.store
        let ok = store.loadError == nil && store.itemCount > 0
        return HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            Text(ok ? "\(store.itemCount) 點" : "無資料").lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill((ok ? Color.green : Color.red).opacity(0.18)))
        .foregroundStyle(ok ? Color.green : Color.red)
    }

    private var speedHero: some View {
        ZStack {
            Circle()
                .strokeBorder(model.driving ? Color.green.opacity(0.5) : Color.white.opacity(0.1),
                              lineWidth: 10)
                .frame(width: 210, height: 210)
            VStack(spacing: -4) {
                Text(String(format: "%.0f", model.speedKph))
                    .font(.system(size: 78, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("km/h").font(.headline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }

    private func nextAlertCard(_ hit: NearbyHit) -> some View {
        HStack(spacing: 14) {
            Image(systemName: hit.item.kind.symbol)
                .font(.title2)
                .foregroundStyle(hit.item.kind.tint)
                .frame(width: 46, height: 46)
                .background(Circle().fill(hit.item.kind.tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.item.kind.displayName).font(.headline)
                Text(hit.item.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(Int(hit.distance)) m").font(.headline).monospacedDigit()
                if let limit = hit.item.limit { SpeedLimitBadge(limit: limit, size: 38) }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(hit.item.kind.tint.opacity(0.35)))
    }

    private var driveButton: some View {
        Button { model.toggleDriving() } label: {
            HStack(spacing: 10) {
                Image(systemName: model.driving ? "stop.fill" : "car.fill")
                Text(model.driving ? "結束行車模式" : "開始行車模式")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(model.driving
                          ? LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
            )
            .foregroundStyle(.white)
            .shadow(color: (model.driving ? Color.red : Color.blue).opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var lastSpoken: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill")
            Text(model.lastAlert).font(.subheadline.weight(.semibold)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.yellow.opacity(0.15)))
        .foregroundStyle(.yellow)
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("前方提醒點").font(.headline)
                Spacer()
                Text(model.driving ? "行車中" : "未開始")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(model.driving ? Color.green : Color.secondary)
            }
            if model.nearest.isEmpty {
                Text(model.driving ? "附近暫無資料點" : "按「開始行車模式」後顯示")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                ForEach(model.nearest) { hit in
                    HStack(spacing: 12) {
                        Image(systemName: hit.item.kind.symbol)
                            .font(.subheadline)
                            .foregroundStyle(hit.item.kind.tint)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(hit.item.kind.tint.opacity(0.16)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.item.kind.displayName).font(.subheadline.weight(.semibold))
                            Text(hit.item.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("\(Int(hit.distance)) m").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        if let limit = hit.item.limit { SpeedLimitBadge(limit: limit, size: 30) }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
                }
            }
        }
    }

    private var footer: some View {
        Text("資料來源：政府資料開放平臺。僅供提醒參考，實際以現場標誌為準。")
            .font(.caption2).foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}
