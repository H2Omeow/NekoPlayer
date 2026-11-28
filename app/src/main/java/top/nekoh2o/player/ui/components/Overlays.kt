package top.nekoh2o.player.ui.components

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import top.nekoh2o.player.ui.theme.NekoSolid

/** 壁纸模式下强制实体底色的对话框，防止底层壁纸透出。 */
@Composable
fun NekoAlertDialog(
    onDismissRequest: () -> Unit,
    confirmButton: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    dismissButton: (@Composable () -> Unit)? = null,
    icon: (@Composable () -> Unit)? = null,
    title: (@Composable () -> Unit)? = null,
    text: (@Composable () -> Unit)? = null,
    containerColor: Color = NekoSolid.dialog
) {
    AlertDialog(
        onDismissRequest = onDismissRequest,
        confirmButton = confirmButton,
        modifier = modifier,
        dismissButton = dismissButton,
        icon = icon,
        title = title,
        text = text,
        containerColor = containerColor
    )
}

/** 壁纸模式下强制实体底色的底部弹窗。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NekoBottomSheet(
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    sheetState: SheetState = rememberModalBottomSheetState(),
    containerColor: Color = NekoSolid.sheet,
    dragHandle: (@Composable () -> Unit)? = { BottomSheetDefaults.DragHandle() },
    content: @Composable ColumnScope.() -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        modifier = modifier,
        sheetState = sheetState,
        containerColor = containerColor,
        dragHandle = dragHandle,
        content = content
    )
}

/** 壁纸模式下强制实体底色的下拉菜单。 */
@Composable
fun NekoDropdownMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    val solid = MaterialTheme.colorScheme.copy(
        surface = NekoSolid.dialog,
        surfaceContainer = NekoSolid.dialog,
        surfaceContainerHigh = NekoSolid.dialog
    )
    MaterialTheme(colorScheme = solid) {
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = onDismissRequest,
            modifier = modifier,
            content = content
        )
    }
}
