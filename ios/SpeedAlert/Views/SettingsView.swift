import SwiftUI
import CoreLocation

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    // Keys come from `AppSettings` so the UI and `AppModel.init()` can never
    // disagree about a key name.
    @AppStorage(AppSettings.autoSpeedKey) private var autoSpeed = AppSettings.autoSpeedDefault
    @AppStorage(AppSettings.s500Key) private var s500 = AppSettings.toggleDefault
    @AppStorage(AppSettings.s300Key) private var s300 = AppSettings.toggleDefault
    @AppStorage(AppSettings.s100Key) private var s100 = AppSettings.toggleDefault
    @AppStorage(AppSettings.s0Key)   private var s0   = AppSettings.toggleDefault
    @AppStorage(AppSettings.kFixedKey)    private var kFixed    = AppSettings.toggleDefault
    @AppStorage(AppSettings.kIntervalKey) private var kInterval = AppSettings.toggleDefault
    @AppStorage(AppSettings.kTechKey)     private var kTech     = AppSettings.toggleDefault
    @AppStorage(AppSettings.kAccidentKey) private var kAccident = AppSettings.toggleDefault
    @AppStorage(AppSettings.voiceRateKey) private var voiceRate = AppSettings.voiceRateDefault

    var body: some View {
        NavigationStack {
            Form {
                Section("提醒距離（公尺）") {
                    Toggle("依車速自動調整", isOn: live($autoSpeed))

                    Group {
                        Toggle("500 公尺", isOn: live($s500))
                        Toggle("300 公尺", isOn: live($s300))
                        Toggle("100 公尺", isOn: live($s100))
                        Toggle("0 公尺（通過）", isOn: live($s0))
                    }
                    .disabled(autoSpeed)

                    Text(autoSpeed
                         ? "已開啟自動調整：時速 60 公里以上用 500／300／100 公尺提醒，時速 30 到 60 公里用 300／100 公尺，時速 30 公里以下用 100 公尺。"
                         : "已關閉自動調整，請選擇要提醒的距離。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("提醒種類") {
                    Toggle("固定式／國道測速", isOn: live($kFixed))
                    Toggle("區間測速", isOn: live($kInterval))
                    Toggle("路口科技執法", isOn: live($kTech))
                    Toggle("易肇事路段", isOn: live($kAccident))
                }

                Section("語音") {
                    VStack(alignment: .leading) {
                        Text("語速：\(String(format: "%.2f", voiceRate))")
                        Slider(value: live($voiceRate), in: AppSettings.voiceRateRange)
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

    /// 寫透（write-through）binding：一改就立刻套用到正在跑的 model。
    ///
    /// 只靠「完成」按鈕套用的話，用下滑手勢關掉設定頁（很常見）就會出現
    /// 「UserDefaults 已經改了、但這一趟行車還是用舊設定」的落差。
    private func live<T>(_ value: Binding<T>) -> Binding<T> {
        Binding(get: { value.wrappedValue },
                set: { newValue in
                    value.wrappedValue = newValue
                    apply()
                })
    }

    /// Push current UI settings into the running model.
    ///
    /// 值統一透過 `AppSettings` 從 `UserDefaults` 讀回（`@AppStorage` 是同步寫入
    /// 的），跟 `AppModel.init()` 走同一條路徑 —— 執行中的 model 與重啟後的
    /// model 因此不可能不一致。
    private func apply() {
        let defaults = UserDefaults.standard
        model.applySettings(manualStages: AppSettings.manualStages(from: defaults),
                            autoSpeed: AppSettings.autoSpeed(from: defaults))
        model.enabledKinds = AppSettings.enabledKinds(from: defaults)
        model.speech.rate = AppSettings.voiceRate(from: defaults)
    }
}
