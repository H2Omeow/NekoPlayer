package top.nekoh2o.player.ui.viewmodel

import top.nekoh2o.player.i18n.NekoI18n.tr

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import top.nekoh2o.player.data.plugins.PluginStore

data class PluginManagerStatus(val loading: Boolean = true, val busy: Boolean = false, val message: String? = null)

class PluginManagerViewModel : ViewModel() {
    val plugins = PluginStore.state
    private val mutableStatus = MutableStateFlow(PluginManagerStatus())
    val status: StateFlow<PluginManagerStatus> = mutableStatus

    init {
        viewModelScope.launch {
            try {
                PluginStore.awaitReady()
                mutableStatus.value = PluginManagerStatus(loading = false)
            } catch (failure: CancellationException) { throw failure }
            catch (_: Exception) { mutableStatus.value = PluginManagerStatus(loading = false, message = tr("音源数据读取失败，已保留原文件")) }
        }
    }

    fun import(location: String, format: String) = perform(tr("音源导入完成")) { PluginStore.importLocation(location, format = format) }
    fun update(id: String) = perform(tr("订阅更新完成")) { PluginStore.update(id) }
    fun enableSubscription(id: String, enabled: Boolean) = perform { PluginStore.setSubscriptionEnabled(id, enabled) }
    fun enablePlugin(id: String, enabled: Boolean) = perform { PluginStore.setPluginEnabled(id, enabled) }
    fun delete(id: String) = perform(tr("已删除外部订阅")) { PluginStore.delete(id) }
    fun configure(id: String, variables: JsonObject) = perform(tr("音源变量已保存")) { PluginStore.configure(id, variables) }
    fun message(value: String) { mutableStatus.value = mutableStatus.value.copy(message = value) }
    fun dismissMessage() { mutableStatus.value = mutableStatus.value.copy(message = null) }

    private fun perform(success: String? = null, action: suspend () -> Unit) {
        if (status.value.loading || status.value.busy) return
        mutableStatus.value = status.value.copy(busy = true, message = null)
        viewModelScope.launch {
            try {
                action()
                mutableStatus.value = mutableStatus.value.copy(message = success)
            } catch (failure: CancellationException) { throw failure }
            catch (failure: Exception) { mutableStatus.value = mutableStatus.value.copy(message = failure.message ?: tr("音源操作失败，原数据已保留")) }
            finally { mutableStatus.value = mutableStatus.value.copy(busy = false) }
        }
    }
}
