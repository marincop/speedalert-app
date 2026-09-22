package tw.speedalert.speech

import android.content.Context
import android.media.MediaPlayer
import java.io.File

/**
 * Modular prerecorded voice pack — mirrors iOS `VoicePack`.
 * Clips live in `assets/VoicePack/<token>.<ext>`. Sentences are assembled from
 * tokens; if any clip is missing, [play] returns false (caller falls back to TTS).
 */
class VoicePack(private val context: Context) {

    private val exts = listOf("m4a", "caf", "mp3", "wav", "aiff", "aif")
    private val players = ArrayList<MediaPlayer>()

    private fun assetPath(token: String): String? {
        for (e in exts) {
            val p = "VoicePack/$token.$e"
            try {
                context.assets.open(p).close()
                return p
            } catch (_: Exception) { /* keep looking */ }
        }
        return null
    }

    val isReady: Boolean get() = assetPath("lead_front") != null

    /** Copy asset to cache (works even if assets are compressed). */
    private fun fileFor(assetPath: String): File {
        val out = File(context.cacheDir, "VoicePack/" + assetPath.substringAfterLast('/'))
        if (!out.exists()) {
            out.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input ->
                out.outputStream().use { input.copyTo(it) }
            }
        }
        return out
    }

    /** Play [tokens] in order. Returns false if any clip is missing. */
    fun play(tokens: List<String>): Boolean {
        if (tokens.isEmpty()) return false
        val paths = ArrayList<String>(tokens.size)
        for (t in tokens) paths.add(assetPath(t) ?: return false)

        stop()
        playFrom(paths, 0)
        return true
    }

    private fun playFrom(paths: List<String>, index: Int) {
        if (index >= paths.size) return
        val mp = MediaPlayer()
        try {
            mp.setDataSource(fileFor(paths[index]).absolutePath)
            mp.setOnCompletionListener {
                it.release()
                players.remove(it)
                playFrom(paths, index + 1)
            }
            mp.prepare()
            mp.start()
            players.add(mp)
        } catch (_: Exception) {
            runCatching { mp.release() }
        }
    }

    fun stop() {
        for (p in players) {
            runCatching { p.stop() }
            runCatching { p.release() }
        }
        players.clear()
    }
}
