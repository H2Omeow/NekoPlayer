package top.nekoh2o.player.data.net

import top.nekoh2o.player.i18n.NekoI18n.tr

import okhttp3.Cookie
import okhttp3.HttpUrl

/** Separate standard/lite cookies; neither session shares the application's SSO cookie jar. */
class KugouSessionStore(private val prefs: ProviderPreferences) {
    private val sessions = Array(2) { platform -> parse(prefs.getString("cookies_" + platform, "").orEmpty()) }

    @Synchronized fun value(platform: Int, name: String): String = sessions[checked(platform)][name].orEmpty()
    @Synchronized fun cookie(platform: Int): String = sessions[checked(platform)].entries.joinToString("; ") { it.key + "=" + it.value }

    @Synchronized fun merge(platform: Int, values: Map<String, String>) {
        val session = sessions[checked(platform)]
        values.filterKeys(::allowed).forEach { (key, value) ->
            if (value.isBlank() || value in listOf("undefined", "null") || value.any { it == ';' || it.code == 13 || it.code == 10 }) {
                session.remove(key)
            } else session[key] = value
        }
        prefs.edit().putString("cookies_" + platform, cookie(platform)).apply()
    }

    @Synchronized fun mergeResponse(platform: Int, url: HttpUrl, headers: List<String>, credentials: Boolean = false) {
        val values = headers.mapNotNull { Cookie.parse(url, it) }.filter {
            allowed(it.name) && (credentials || it.name !in AUTH_NAMES)
        }.associate { it.name to if (it.expiresAt <= System.currentTimeMillis()) "" else it.value }
        merge(platform, values)
    }

    @Synchronized fun commitLogin(platform: Int, url: HttpUrl, headers: List<String>, token: String, userid: Long, dfid: String) {
        val values = AUTH_NAMES.associateWith { "" }.toMutableMap()
        headers.mapNotNull { Cookie.parse(url, it) }.filter { allowed(it.name) }.forEach {
            values[it.name] = if (it.expiresAt <= System.currentTimeMillis()) "" else it.value
        }
        values["token"] = token
        values["userid"] = userid.toString()
        if (dfid.isNotBlank()) values["dfid"] = dfid
        merge(platform, values)
    }

    @Synchronized fun clearLogin(platform: Int) = merge(platform, AUTH_NAMES.associateWith { "" })

    /** Validate the entire import before changing an existing account. */
    @Synchronized fun importCookie(platform: Int, raw: String) {
        checked(platform)
        require(raw.length <= 16384 && raw.none { it.code < 32 || it.code > 126 }) {
            tr("Cookie 必须是单行文本，且不超过 16384 字符")
        }
        val content = raw.trim().replaceFirst(Regex("^Cookie: *", RegexOption.IGNORE_CASE), "")
        val values = linkedMapOf<String, String>()
        content.split(';').filter(String::isNotBlank).forEach { part ->
            val index = part.indexOf('=')
            require(index > 0) { tr("Cookie 格式应为 token=…; userid=…") }
            val name = part.substring(0, index).trim()
            val value = part.substring(index + 1).trim()
            if (allowed(name)) {
                require(name !in values) { tr("Cookie 包含重复字段，请检查后重试") }
                require(value.isNotBlank() && value !in setOf("null", "undefined") &&
                    value.none { it.isWhitespace() }) { tr("Cookie 包含无效字段，请检查后重试") }
                values[name] = value
            }
        }
        val userid = values["userid"]?.toLongOrNull()?.takeIf { it > 0 }
        require(!values["token"].isNullOrBlank() && userid != null) {
            tr("酷狗 Cookie 必须包含有效的 token 和 userid；仅有网页追踪 Cookie 无法登录")
        }
        values["userid"] = userid.toString()
        // Never carry VIP credentials from the previous account into an imported account.
        merge(platform, AUTH_NAMES.associateWith { "" } + values)
    }

    @Synchronized fun clearCookie(platform: Int) {
        sessions[checked(platform)].clear()
        prefs.edit().remove("cookies_" + platform).apply()
    }

    @Synchronized fun migrate(platform: Int, token: String, userid: String, dfid: String) {
        if (prefs.getBoolean("legacy_migrated", false)) return
        if (cookie(platform).isEmpty()) merge(platform, mapOf("token" to token, "userid" to userid, "dfid" to dfid))
        prefs.edit().putBoolean("legacy_migrated", true).apply()
    }

    private fun checked(platform: Int): Int { require(platform in 0..1); return platform }

    companion object {
        private val AUTH_NAMES = setOf("token", "userid", "vip_type", "vip_token", "t1")
        private fun allowed(name: String) = name in AUTH_NAMES || name == "dfid" || name.startsWith("KUGOU_API_")
        private fun parse(raw: String): MutableMap<String, String> = raw.split(';').mapNotNull { part ->
            val i = part.indexOf('=')
            if (i <= 0) return@mapNotNull null
            val key = part.substring(0, i).trim()
            val value = part.substring(i + 1).trim()
            if (!allowed(key) || value.isEmpty() || value in listOf("undefined", "null")) null else key to value
        }.toMap().toMutableMap()
    }
}
