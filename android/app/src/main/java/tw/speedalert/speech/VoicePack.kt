package tw.speedalert.speech

import android.content.Context
import android.media.MediaPlayer
import java.io.File
import java.io.OutputStream

/**
 * Modular prerecorded voice pack — mirrors iOS `VoicePack`.
 * Clips live in `assets/VoicePack/<token>.<ext>`.
 *
 * For seamless sentences, consecutive `.mp3` clips are **byte-concatenated**
 * into a single temp file and played once (avoids the gap you get by chaining
 * MediaPlayers). Falls back to sequential playback for non-mp3 packs.
 */
class VoicePack(private val context: Context) {

    private val exts = listOf("mp3", "m4a", "caf", "wav", "aiff", "aif")
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

    /** Play [tokens] as one seamless sentence. Returns false if any clip is missing. */
    fun play(tokens: List<String>): Boolean {
        if (tokens.isEmpty()) return false
        val paths = ArrayList<String>(tokens.size)
        for (t in tokens) paths.add(assetPath(t) ?: return false)

        if (paths.all { it.endsWith(".mp3", ignoreCase = true) }) {
            concatMp3(paths)?.let { if (playFile(it)) return true }
        }
        stop()
        playFrom(paths, 0)   // fallback: sequential
        return true
    }

    // ---- seamless concatenation -------------------------------------------

    private fun concatMp3(paths: List<String>): File? = try {
        val key = Integer.toHexString(paths.joinToString("|").hashCode())
        val out = File(context.cacheDir, "VoicePack/seq_$key.mp3")
        out.parentFile?.mkdirs()
        out.outputStream().use { os -> paths.forEach { copyAssetSkippingId3(it, os) } }
        out
    } catch (_: Throwable) { null }

    /** Copy an mp3 asset, skipping a leading ID3v2 tag if present. */
    private fun copyAssetSkippingId3(assetPath: String, os: OutputStream) {
        context.assets.open(assetPath).use { input ->
            val bytes = input.readBytes()
            var off = 0
            if (bytes.size > 10 && bytes[0] == 0x49.toByte() &&
                bytes[1] == 0x44.toByte() && bytes[2] == 0x33.toByte()
            ) {
                val size = ((bytes[6].toInt() and 0x7f) shl 21) or
                        ((bytes[7].toInt() and 0x7f) shl 14) or
                        ((bytes[8].toInt() and 0x7f) shl 7) or
                        (bytes[9].toInt() and 0x7f)
                off = (10 + size).coerceAtMost(bytes.size)
            }
            os.write(bytes, off, bytes.size - off)
        }
    }

    private fun playFile(f: File): Boolean {
        stop()
        val mp = MediaPlayer()
        return try {
            mp.setDataSource(f.absolutePath)
            mp.prepare()
            mp.start()
            players.add(mp)
            true
        } catch (_: Throwable) {
            runCatching { mp.release() }
            false
        }
    }

    // ---- fallback: sequential ---------------------------------------------

    private fun playFrom(paths: List<String>, index: Int) {
        if (index >= paths.size) return
        val mp = MediaPlayer()
        try {
            mp.setDataSource(cacheFile(paths[index]).absolutePath)
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

    private fun cacheFile(assetPath: String): File {
        val out = File(context.cacheDir, "VoicePack/" + assetPath.substringAfterLast('/'))
        if (!out.exists()) {
            out.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input -> out.outputStream().use { input.copyTo(it) } }
        }
        return out
    }

    fun stop() {
        for (p in players) {
            runCatching { p.stop() }
            runCatching { p.release() }
        }
        players.clear()
    }
}
