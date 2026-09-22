package tw.speedalert.alert

import tw.speedalert.model.EnforcementItem
import tw.speedalert.model.EnforcementKind
import tw.speedalert.model.NearbyHit

/**
 * Multi-stage alert engine — mirrors iOS `AlertEngine`.
 * Fires at 500/300/100/0(passed) m per point, once per approach.
 */
class AlertEngine(stages: List<Double> = DEFAULT_STAGES) {

    private var stages: List<Double> = stages.sortedDescending()
    private val state = HashMap<Int, St>()

    private class St(
        val fired: MutableSet<Int> = HashSet(),
        var last: Double = Double.MAX_VALUE,
        var passed: Boolean = false
    )

    /** (spoken text, item, stage) */
    var onAlert: ((String, EnforcementItem, Double) -> Unit)? = null

    fun updateStages(newStages: List<Double>) {
        stages = newStages.sortedDescending()
        state.clear()
    }

    fun reset() = state.clear()

    /** Process the nearby hits for one GPS fix. `hits` should cover >= 600 m. */
    fun process(hits: List<NearbyHit>) {
        val maxStage = stages.firstOrNull() ?: 500.0
        for (hit in hits) {
            val id = hit.item.id
            val d = hit.distance
            val st = state.getOrPut(id) { St() }

            if (d > maxStage * 1.5) { state.remove(id); continue }

            if (stages.contains(0.0) && !st.passed && st.last < 60 && d > st.last + 5) {
                st.passed = true
                st.fired.add(0)
                emit(hit.item, 0.0)
            }
            for (s in stages) {
                if (s > 0 && d <= s && !st.fired.contains(s.toInt())) {
                    st.fired.add(s.toInt())
                    emit(hit.item, s)
                }
            }
            st.last = d
        }
    }

    private fun emit(item: EnforcementItem, stage: Double) =
        onAlert?.invoke(AlertPhrase.text(item, stage), item, stage)

    companion object { val DEFAULT_STAGES = listOf(500.0, 300.0, 100.0, 0.0) }
}

/** Sentence + voice-pack token builder — mirrors iOS `AlertPhrase`. */
object AlertPhrase {

    fun text(item: EnforcementItem, stage: Double): String {
        val noun = item.kind.spokenNoun
        if (stage == 0.0) return "已通過$noun"
        val dist = "前方${chinese(stage.toInt())}公尺"
        return if (item.kind == EnforcementKind.ACCIDENT_SEGMENT) {
            "${dist}易肇事路段，請小心駕駛"
        } else {
            item.limit?.let { "$dist$noun，限速${chinese(it)}公里" } ?: "$dist$noun"
        }
    }

    fun tokens(item: EnforcementItem, stage: Double): List<String> {
        val kind = item.kind.voiceToken
        if (stage == 0.0) return listOf("passed", kind)
        val t = mutableListOf("lead_front", "dist_${stage.toInt()}", "unit_m")
        if (item.kind == EnforcementKind.ACCIDENT_SEGMENT) {
            t += listOf("kind_accident", "accident_warn")
        } else {
            t += kind
            item.limit?.let { t += listOf("limit_pre", "num_$it", "limit_post") }
        }
        return t
    }

    /** 500 -> 五百, 50 -> 五十 (0..9999). */
    fun chinese(n: Int): String {
        if (n <= 0) return "零"
        val digits = listOf("零", "一", "二", "三", "四", "五", "六", "七", "八", "九")
        val units = listOf("", "十", "百", "千")
        val s = n.toString()
        val out = StringBuilder()
        val len = s.length
        for ((i, ch) in s.withIndex()) {
            val d = ch - '0'
            val pos = len - i - 1
            if (d == 0) {
                if (out.isNotEmpty() && out.last() != '零') out.append('零')
                continue
            }
            if (pos == 1 && d == 1 && out.isEmpty()) { out.append('十'); continue }
            out.append(digits[d]).append(units[pos])
        }
        while (out.isNotEmpty() && out.last() == '零') out.deleteCharAt(out.length - 1)
        return out.toString()
    }
}
