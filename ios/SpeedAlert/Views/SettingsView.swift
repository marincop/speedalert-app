import SwiftUI
import CoreLocation

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("s500") private var s500 = true
    @AppStorage("s300") private var s300 = true
    @AppStorage("s100") private var s100 = true
    @AppStorage("s0")   private var s0   = true
    @AppStorage("k_fixed")   private var kFixed = true
    @AppStorage("k_interval") private var kInterval = true
    @AppStorage("k_tech")    private var kTech = true
    @AppStorage("k_accident") private var kAccident = true
    @AppStorage("voiceRate") private var voiceRate = 0.5

    var body: some View {
        NavigationStack {
            Form {
                Section("提醒距離（公尺）") {
                    Toggle("500 公尺", isOn: $s500)
                    Toggle("300 公尺", isOn: $s300)
                    Toggle("100 公尺", isOn: $s100)
                    Toggle("0 公尺（通過）", isOn: $s0)
                }

                Section("提醒種類") {
                    Toggle("固定式／國道測速", isOn: $kFixed)
                    Toggle("區間測速", isOn: $kInterval)
                    Toggle("路口科技執法", isOn: $kTech)
                    Toggle("易肇事路段", isOn: $kAccident)
                }

                Section("語音") {
                    VStack(alignment: .leading) {
                        Text("語速：\(String(format: "%.2f", voiceRate))")
                        Slider(value: $voiceRate, in: 0.3...0.7)
                    }
                    Text("語音：\(model.speech.voiceName)")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("試聽語音") {
                        model.speech.speak(
                            text: "前方三百公尺測速照相，限速五十公里",
                            tokens: ["lead_front", "dist_300", "unit_m", "kind_fixed",
                                     "limit_pre", "num_50", "limit_post"],
                            force: true)
                    }
                }

                Section("資料") {
                    LabeledContent("資料點總數", value: "\(model.store.itemCount)")
                    LabeledContent("資料版本", value: model.store.builtAt ?? "—")
                    Text("來源：政府資料開放平臺（警政署、各縣市警察局）。僅供提醒參考，實際以現場標誌為準。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { apply(); dismiss() }
                }
            }
            .onAppear(perform: apply)
        }
    }

    /// Push current UI settings into the running model.
    private func apply() {
        var stages: [CLLocationDistance] = []
        if s500 { stages.append(500) }
        if s300 { stages.append(300) }
        if s100 { stages.append(100) }
        if s0   { stages.append(0) }
        model.stages = stages.isEmpty ? AlertEngine.defaultStages : stages

        var kinds: Set<EnforcementKind> = []
        if kFixed    { kinds.insert(.fixedSpeed); kinds.insert(.highwaySpeed) }
        if kInterval { kinds.insert(.intervalSpeed) }
        if kTech     { kinds.insert(.techIntersection); kinds.insert(.techOther) }
        if kAccident { kinds.insert(.accidentSegment) }
        model.enabledKinds = kinds
        model.speech.rate = Float(voiceRate)
    }
}
