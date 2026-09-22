package tw.speedalert.data

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import tw.speedalert.model.EnforcementItem
import tw.speedalert.model.EnforcementKind
import tw.speedalert.model.NearbyHit
import tw.speedalert.util.Geo
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max

/**
 * Loads the bundled offline dataset (`assets/app_data.json`) and answers
 * proximity queries via a ~2.2 km grid index. Mirrors iOS `EnforcementStore`.
 */
class EnforcementStore(private val context: Context) {

    var items: List<EnforcementItem> = emptyList(); private set
    var builtAt: String? = null; private set
    var loadError: String? = null; private set

    private val cell = 0.02
    private val metersPerDegLat = 111_320.0
    private val grid = HashMap<Long, MutableList<Int>>()

    init { load() }

    private fun load() {
        try {
            val text = context.assets.open("app_data.json").bufferedReader().use { it.readText() }
            val root = JSONObject(text)
            builtAt = if (root.isNull("built_at")) null else root.optString("built_at")

            val list = ArrayList<EnforcementItem>()
            addCameras(root.optJSONArray("cameras"), list)
            addSections(root.optJSONArray("sections"), list)
            addAccidents(root.optJSONArray("accidents"), list)

            items = list
            buildIndex()
            loadError = null
            Log.i(TAG, "loaded ${items.size} items (built=$builtAt)")
        } catch (t: Throwable) {
            loadError = "load failed: ${t.message}"
            Log.e(TAG, "load failed", t)
        }
    }

    private fun addCameras(arr: JSONArray?, out: MutableList<EnforcementItem>) {
        if (arr == null) return
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val kind = EnforcementKind.from(o.optString("kind")) ?: continue
            out.add(
                EnforcementItem(
                    id = o.getInt("id"), kind = kind,
                    lat = o.getDouble("lat"), lon = o.getDouble("lon"),
                    limit = o.optIntOrNull("limit"), dir = o.optStringOrNull("dir"),
                    addr = o.optStringOrNull("addr"), city = o.optStringOrNull("city")
                )
            )
        }
    }

    private fun addSections(arr: JSONArray?, out: MutableList<EnforcementItem>) {
        if (arr == null) return
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            out.add(
                EnforcementItem(
                    id = 1_000_000 + o.getInt("id"), kind = EnforcementKind.INTERVAL_SPEED,
                    lat = o.getDouble("lat"), lon = o.getDouble("lon"),
                    limit = o.optIntOrNull("limit"), dir = null,
                    addr = o.optStringOrNull("name"), city = o.optStringOrNull("city")
                )
            )
        }
    }

    private fun addAccidents(arr: JSONArray?, out: MutableList<EnforcementItem>) {
        if (arr == null) return
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.isNull("lat") || o.isNull("lon")) continue
            out.add(
                EnforcementItem(
                    id = 2_000_000 + o.getInt("id"), kind = EnforcementKind.ACCIDENT_SEGMENT,
                    lat = o.getDouble("lat"), lon = o.getDouble("lon"),
                    limit = null, dir = null,
                    addr = o.optStringOrNull("name"), city = o.optStringOrNull("city")
                )
            )
        }
    }

    private fun JSONObject.optIntOrNull(key: String): Int? =
        if (isNull(key)) null else optInt(key).takeIf { has(key) }

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (isNull(key)) null else optString(key).ifBlank { null }

    private fun key(latCell: Int, lonCell: Int): Long =
        (latCell.toLong() shl 32) xor (lonCell.toLong() and 0xffffffffL)

    private fun buildIndex() {
        grid.clear()
        items.forEachIndexed { i, it ->
            val k = key(floor(it.lat / cell).toInt(), floor(it.lon / cell).toInt())
            grid.getOrPut(k) { ArrayList() }.add(i)
        }
    }

    /** Items within [radius] metres of (lat,lon), nearest first. */
    fun nearby(
        lat: Double, lon: Double, radius: Double,
        kinds: Set<EnforcementKind> = EnforcementKind.entries.toSet()
    ): List<NearbyHit> {
        val latSpan = ceil(radius / (cell * metersPerDegLat)).toInt() + 1
        val lonScale = max(cos(Math.toRadians(lat)), 0.1)
        val lonSpan = ceil(radius / (cell * metersPerDegLat * lonScale)).toInt() + 1
        val latCell = floor(lat / cell).toInt()
        val lonCell = floor(lon / cell).toInt()

        val out = ArrayList<NearbyHit>()
        val seen = HashSet<Int>()
        for (dy in -latSpan..latSpan) {
            for (dx in -lonSpan..lonSpan) {
                val ids = grid[key(latCell + dy, lonCell + dx)] ?: continue
                for (i in ids) {
                    if (!seen.add(i)) continue
                    val it = items[i]
                    if (it.kind !in kinds) continue
                    val d = Geo.distance(lat, lon, it.lat, it.lon)
                    if (d <= radius) out.add(NearbyHit(it, d, Geo.bearing(lat, lon, it.lat, it.lon)))
                }
            }
        }
        out.sortBy { it.distance }
        return out
    }

    private companion object { const val TAG = "SpeedAlert" }
}
