package tw.speedalert.speech

import android.content.Context
import android.speech.tts.TextToSpeech
import java.util.Locale

/**
 * Speech output — mirrors iOS `SpeechService`.
 * Prefers the prerecorded [VoicePack]; falls back to system TTS (zh-TW).
 */
class SpeechService(private val context: Context) {

    private val voicePack = VoicePack(context)
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    private var lastText = ""
    private var lastAt = 0L

    init {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale("zh", "TW")
                ttsReady = true
            }
        }
    }

    /** Speak via voice pack if available, else TTS. */
    fun speak(text: String, tokens: List<String>? = null, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && text == lastText && now - lastAt < 4000) return
        lastText = text
        lastAt = now

        if (tokens != null && tokens.isNotEmpty() && voicePack.play(tokens)) return
        if (ttsReady) {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "speedalert")
        }
    }

    val voicePackReady: Boolean get() = voicePack.isReady

    fun shutdown() {
        voicePack.stop()
        tts?.shutdown()
        tts = null
    }
}
