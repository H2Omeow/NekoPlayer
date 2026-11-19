package top.nekoh2o.player.ui.screens.cloud

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.ui.theme.NekoSolid
import top.nekoh2o.player.ui.theme.NekoSpace

/** 点满 7 次才触发的小彩蛋计数（只存在内存里，重启就清零）。 */
object MemeTaps {
    private const val NEED = 7
    private val counts = mutableMapOf<String, Int>()

    fun tap(kind: String): Boolean {
        val next = (counts[kind] ?: 0) + 1
        counts[kind] = next
        if (next >= NEED) counts[kind] = 0
        return next >= NEED
    }
}

@Composable
fun MemeText(
    text: String,
    kind: String,
    style: TextStyle = MaterialTheme.typography.bodyMedium,
    color: Color = Color.Unspecified,
    onTrigger: (String) -> Unit
) {
    Text(
        text,
        style = style,
        color = color,
        modifier = Modifier.clickable { if (MemeTaps.tap(kind)) onTrigger(kind) }
    )
}

data class MemeCopy(val title: String, val body: String)

fun memeCopy(kind: String): MemeCopy = when (kind) {
    "325" -> MemeCopy(
        "325 大学习",
        "仙术杯第五届「冠军厨小队」的魔法Zc目录在 2024-03-11 初赛结算拿到 325 分；因为本姓周，弹幕把「325」当成 325 个「周」。后来干脆成了计量单位：325 周。\n\n" +
            "（同场他还有 70 分加分，总分 395，但大家只记得 325。）"
    )
    "799" -> MemeCopy(
        "799 的来历",
        "提丰满配 X 模组、二技能打 0–2 重敌人时的对单 DPS：\n" +
            "(1189 + 90) × 1.5 ÷ 2.4 = 799.375\n\n" +
            "算法刻意不算无视防御、首次加攻和高重加攻，还把二连击折半，所以刚好落在 799 上。"
    )
    else -> MemeCopy("彩蛋", "你发现了点什么。")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MemeSheet(kind: String, onDismiss: () -> Unit) {
    val copy = memeCopy(kind)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = NekoSolid.sheet
    ) {
        Column(Modifier.fillMaxWidth().padding(horizontal = NekoSpace.xl)) {
            Text(copy.title, style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(NekoSpace.sm))
            Text(
                copy.body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(36.dp))
        }
    }
}
