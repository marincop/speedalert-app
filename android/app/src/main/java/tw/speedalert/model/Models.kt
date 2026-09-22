package tw.speedalert.model

/** Hazard / enforcement kind — mirrors iOS `EnforcementKind`. */
enum class EnforcementKind(val raw: String, val displayName: String) {
    FIXED_SPEED("fixed_speed", "固定式測速"),
    HIGHWAY_SPEED("highway_speed", "國道測速"),
    INTERVAL_SPEED("interval_speed", "區間測速"),
    TECH_INTERSECTION("tech_intersection", "路口科技執法"),
    TECH_OTHER("tech_other", "科技執法"),
    ACCIDENT_SEGMENT("accident_segment", "易肇事路段");

    /** Noun used in spoken/visible sentences. */
    val spokenNoun: String
        get() = when (this) {
            FIXED_SPEED, HIGHWAY_SPEED -> "測速照相"
            INTERVAL_SPEED -> "區間測速"
            TECH_INTERSECTION, TECH_OTHER -> "科技執法"
            ACCIDENT_SEGMENT -> "易肇事路段"
        }

    /** Voice-pack clip token for this kind. */
    val voiceToken: String
        get() = when (this) {
            FIXED_SPEED, HIGHWAY_SPEED -> "kind_fixed"
            INTERVAL_SPEED -> "kind_interval"
            TECH_INTERSECTION, TECH_OTHER -> "kind_tech"
            ACCIDENT_SEGMENT -> "kind_accident"
        }

    companion object {
        fun from(raw: String): EnforcementKind? = entries.firstOrNull { it.raw == raw }
    }
}

data class EnforcementItem(
    val id: Int,
    val kind: EnforcementKind,
    val lat: Double,
    val lon: Double,
    val limit: Int?,
    val dir: String?,
    val addr: String?,
    val city: String?
) {
    val label: String get() = addr ?: city ?: kind.displayName
}

data class NearbyHit(
    val item: EnforcementItem,
    val distance: Double,
    val bearing: Double
) {
    val id: Int get() = item.id
}
