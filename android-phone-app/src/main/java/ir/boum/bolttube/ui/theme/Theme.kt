package ir.boum.bolttube.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(
    primary = BoltBlue,
    secondary = BoltMint,
    tertiary = BoltBlueDark,
    background = BoltSand,
    surface = BoltSand,
    onPrimary = androidx.compose.ui.graphics.Color.White,
    onBackground = BoltInk,
    onSurface = BoltInk,
)

private val DarkColors = darkColorScheme(
    primary = BoltMint,
    secondary = BoltBlue,
    tertiary = BoltBlueDark,
)

@Composable
fun BoltTubeTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColors,
        typography = Typography,
        content = content,
    )
}
