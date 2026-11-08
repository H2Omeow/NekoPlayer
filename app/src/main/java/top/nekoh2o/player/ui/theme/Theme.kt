package top.nekoh2o.player.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Shapes
import androidx.compose.material3.TextFieldColors
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/** 间距刻度，与桌面端 NekoSpace 一致。页面布局只用这些值。 */
object NekoSpace {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 24.dp
    val xxl = 32.dp
}

/** 圆角刻度，与桌面端 NekoRadius 一致。 */
object NekoRadius {
    val cover = 8.dp
    val control = 10.dp
    val card = 16.dp
    val artwork = 20.dp
    val sheet = 28.dp
}

// 与桌面端深色方案同色，两端视觉一致
private val Scheme = darkColorScheme(
    primary = Color(0xFFF0546E),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFF4B1A26),
    onPrimaryContainer = Color(0xFFFFD9DF),
    inversePrimary = Color(0xFFB8304B),
    secondary = Color(0xFFC9C3CB),
    onSecondary = Color(0xFF1D1B1E),
    secondaryContainer = Color(0xFF333034),
    onSecondaryContainer = Color(0xFFF2EEF2),
    tertiary = Color(0xFF8FCBC4),
    onTertiary = Color(0xFF00201D),
    tertiaryContainer = Color(0xFF1F3B38),
    onTertiaryContainer = Color(0xFFB7EDE6),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF0B0A0C),
    onBackground = Color(0xFFEEEAEE),
    surface = Color(0xFF141315),
    onSurface = Color(0xFFEEEAEE),
    surfaceVariant = Color(0xFF353336),
    onSurfaceVariant = Color(0xFFABA6AE),
    surfaceDim = Color(0xFF0B0A0C),
    surfaceBright = Color(0xFF3A383B),
    surfaceContainerLowest = Color(0xFF0B0A0C),
    surfaceContainerLow = Color(0xFF1B1A1C),
    surfaceContainer = Color(0xFF211F22),
    surfaceContainerHigh = Color(0xFF2A282B),
    surfaceContainerHighest = Color(0xFF353336),
    outline = Color(0xFF7A757D),
    outlineVariant = Color(0xFF302E32),
    // 关掉 tonal elevation 染色，否则 Surface 会把调透明的颜色重新叠成不透明
    surfaceTint = Color.Transparent,
    inverseSurface = Color(0xFFEEEAEE),
    inverseOnSurface = Color(0xFF1D1B1E),
    scrim = Color(0xFF000000)
)

private fun style(size: Int, weight: FontWeight, height: Float) = TextStyle(
    fontSize = size.sp,
    fontWeight = weight,
    lineHeight = (size * height).sp,
    letterSpacing = 0.em
)

// 与桌面端字号层级一致；移动端正文略大一号以便阅读
private val NekoTypography = Typography(
    displaySmall = style(32, FontWeight.Bold, 1.25f),
    headlineMedium = style(28, FontWeight.Bold, 1.3f),
    headlineSmall = style(24, FontWeight.Bold, 1.3f),
    titleLarge = style(20, FontWeight.SemiBold, 1.35f),
    titleMedium = style(16, FontWeight.SemiBold, 1.4f),
    titleSmall = style(14, FontWeight.SemiBold, 1.4f),
    bodyLarge = style(16, FontWeight.Normal, 1.45f),
    bodyMedium = style(14, FontWeight.Normal, 1.45f),
    bodySmall = style(12, FontWeight.Normal, 1.45f),
    labelLarge = style(14, FontWeight.SemiBold, 1.3f),
    labelMedium = style(12, FontWeight.Medium, 1.3f),
    labelSmall = style(11, FontWeight.Medium, 1.3f)
)

/**
 * 全局主题。始终为深色：壁纸背景上需要浅色文字。
 *
 * @param controlAlpha 控件不透明度，0 全透明、1 不透明。仅在 [translucent] 为 true 时生效。
 * @param translucent 是否开启壁纸背景。开启后 surface / container 系列颜色统一按
 *   [controlAlpha] 变半透明，Card、ListItem、TopAppBar、对话框等控件都会跟着透明。
 * @param uiScale UI 缩放倍率（0.8 ~ 1.3），保留系统字体缩放，不重复放大文字
 */
@Composable
fun NekoTheme(
    controlAlpha: Float = 1f,
    translucent: Boolean = false,
    uiScale: Float = 1.0f,
    content: @Composable () -> Unit
) {
    val density = LocalDensity.current
    val scaledDensity = remember(uiScale, density) {
        Density(density.density * uiScale.coerceIn(0.8f, 1.3f), density.fontScale)
    }
    val colors = if (translucent) Scheme.withControlAlpha(controlAlpha) else Scheme

    MaterialTheme(
        colorScheme = colors,
        typography = NekoTypography,
        shapes = Shapes(
            extraSmall = RoundedCornerShape(NekoRadius.cover),
            small = RoundedCornerShape(NekoRadius.control),
            medium = RoundedCornerShape(NekoRadius.card),
            large = RoundedCornerShape(NekoRadius.artwork),
            extraLarge = RoundedCornerShape(NekoRadius.sheet)
        )
    ) {
        // 壁纸开启时 Scaffold 是透明色，contentColorFor(Transparent) 推不出文字色，
        // 会回退到根级 LocalContentColor（默认黑）。这里兜底为 onSurface。
        CompositionLocalProvider(
            LocalContentColor provides colors.onSurface,
            LocalDensity provides scaledDensity,
            content = content
        )
    }
}

/**
 * 把 surface / container 系列统一改成半透明，让壁纸透出来。
 *
 * 不动 background：壁纸层由 MainScaffold 自己铺，壁纸缺失时需要不透明兜底色。
 */
private fun ColorScheme.withControlAlpha(alpha: Float): ColorScheme {
    val a = alpha.coerceIn(0f, 1f)
    fun Color.dim() = copy(alpha = a)
    return copy(
        surface = surface.dim(),
        surfaceVariant = surfaceVariant.dim(),
        surfaceBright = surfaceBright.dim(),
        surfaceDim = surfaceDim.dim(),
        surfaceContainer = surfaceContainer.dim(),
        surfaceContainerLow = surfaceContainerLow.dim(),
        surfaceContainerLowest = surfaceContainerLowest.dim(),
        surfaceContainerHigh = surfaceContainerHigh.dim(),
        surfaceContainerHighest = surfaceContainerHighest.dim()
    )
}

/**
 * 文字类控件的中性默认值。
 *
 * TextButton / OutlinedButton 默认用 primary 着色，大面积使用时太跳；这里改为正文色，
 * primary 只留给主要操作、选中状态和收藏。
 */
object NekoDefaults {

    @Composable
    fun textButtonColors(): ButtonColors =
        ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)

    @Composable
    fun outlinedButtonColors(): ButtonColors =
        ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)

    @Composable
    fun textFieldColors(): TextFieldColors {
        val c = MaterialTheme.colorScheme
        return OutlinedTextFieldDefaults.colors(
            focusedTextColor = c.onSurface,
            unfocusedTextColor = c.onSurface,
            focusedLabelColor = c.primary,
            unfocusedLabelColor = c.onSurfaceVariant,
            focusedPlaceholderColor = c.onSurfaceVariant,
            unfocusedPlaceholderColor = c.onSurfaceVariant,
            cursorColor = c.primary,
            focusedBorderColor = c.primary,
            unfocusedBorderColor = c.outline,
            focusedContainerColor = c.surfaceContainerLow,
            unfocusedContainerColor = c.surfaceContainerLow,
            focusedTrailingIconColor = c.onSurface,
            unfocusedTrailingIconColor = c.onSurfaceVariant,
            focusedLeadingIconColor = c.onSurface,
            unfocusedLeadingIconColor = c.onSurfaceVariant
        )
    }
}
