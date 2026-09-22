package tw.speedalert.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val BgTop = Color(0xFF121A2B)
val BgBot = Color(0xFF04060D)
val CardBg = Color(0x14FFFFFF)      // white @ ~8%
val CardBg2 = Color(0x0DFFFFFF)

private val Scheme = darkColorScheme(
    primary = Color(0xFF3B82F6),
    onPrimary = Color.White,
    secondary = Color(0xFF22D3EE),
    background = BgBot,
    surface = Color(0xFF141A28),
    onSurface = Color(0xFFE8EAF0)
)

@Composable
fun SpeedAlertTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = Scheme, content = content)
}
