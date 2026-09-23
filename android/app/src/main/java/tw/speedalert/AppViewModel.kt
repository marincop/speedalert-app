package tw.speedalert

import android.app.Application
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import tw.speedalert.alert.AlertEngine
import tw.speedalert.alert.AlertPhrase
import tw.speedalert.data.EnforcementStore
import tw.speedalert.location.DrivingService
import tw.speedalert.location.LocationBus
import tw.speedalert.location.SpeedFilter
import tw.speedalert.model.EnforcementKind
import tw.speedalert.model.NearbyHit
import tw.speedalert.speech.SpeechService

/** Orchestrates store + location + alert engine + speech. Mirrors iOS `AppModel`. */
class AppViewModel(app: Application) : AndroidViewModel(app) {

    val store = EnforcementStore(app)
    private val speech = SpeechService(app)
    private val engine = AlertEngine()
    private val speedFilter = SpeedFilter()

    private val _driving = MutableStateFlow(false)
    val driving: StateFlow<Boolean> = _driving

    private val _speed = MutableStateFlow(0.0)
    val speed: StateFlow<Double> = _speed

    private val _nearest = MutableStateFlow<List<NearbyHit>>(emptyList())
    val nearest: StateFlow<List<NearbyHit>> = _nearest

    private val _lastAlert = MutableStateFlow("")
    val lastAlert: StateFlow<String> = _lastAlert

    var enabledKinds: Set<EnforcementKind> = EnforcementKind.entries.toSet()
    var stages: List<Double> = AlertEngine.DEFAULT_STAGES
        set(value) {
            field = value
            engine.updateStages(value)
        }

    private val queryRadius = 600.0

    init {
        engine.onAlert = { text, item, stage ->
            speech.speak(text, AlertPhrase.tokens(item, stage))
            _lastAlert.value = text
        }
        viewModelScope.launch {
            LocationBus.location.collect { loc ->
                if (loc != null && _driving.value) {
                    handle(loc.latitude, loc.longitude, loc.speed.toDouble())
                }
            }
        }
        // 靜止看門狗：每秒刷新顯示速度，讓停下後（系統不再送點）也能歸零。
        viewModelScope.launch {
            while (true) {
                delay(1000)
                if (_driving.value) _speed.value = speedFilter.value(SystemClock.elapsedRealtime())
            }
        }
    }

    private fun handle(lat: Double, lon: Double, speedMps: Double) {
        speedFilter.update(speedMps, SystemClock.elapsedRealtime())
        _speed.value = speedFilter.value(SystemClock.elapsedRealtime())
        val hits = store.nearby(lat, lon, queryRadius, enabledKinds)
        _nearest.value = hits.take(8)
        engine.process(hits)
    }

    fun toggleDriving() {
        val app = getApplication<Application>()
        if (_driving.value) {
            app.stopService(Intent(app, DrivingService::class.java))
            _driving.value = false
            _nearest.value = emptyList()
            speedFilter.reset()
            _speed.value = 0.0
        } else {
            engine.reset()
            val intent = Intent(app, DrivingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                app.startForegroundService(intent)
            } else {
                app.startService(intent)
            }
            _driving.value = true
        }
    }

    fun previewVoice() {
        speech.speak(
            "前方三百公尺測速照相，限速五十公里",
            listOf("lead_front", "dist_300", "unit_m", "kind_fixed", "limit_pre", "num_50", "limit_post"),
            force = true
        )
    }

    override fun onCleared() {
        speech.shutdown()
        super.onCleared()
    }
}
