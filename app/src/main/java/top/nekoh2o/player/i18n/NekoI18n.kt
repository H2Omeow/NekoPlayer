package top.nekoh2o.player.i18n

import android.app.Activity
import android.app.LocaleManager
import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import org.json.JSONObject
import java.util.Locale

/**
 * Runtime catalog lookup. The catalog key is the normalized Simplified Chinese
 * source string; missing entries fall back to the source text.
 */
object NekoI18n {
    const val SYSTEM = "system"
    const val ZH_CN = "zh-CN"
    const val ZH_TW = "zh-TW"
    const val EN = "en"
    const val JA = "ja"

    val supportedTags = listOf(ZH_CN, ZH_TW, EN, JA)

    @Volatile
    var selectedTag: String = SYSTEM
        private set

    @Volatile
    private var activeTag: String = ZH_CN

    @Volatile
    private var table: Map<String, Any> = emptyMap()

    private val placeholder = Regex("\\{([A-Za-z_][A-Za-z0-9_]*)\\}")

    fun initialize(context: Context) {
        val app = context.applicationContext
        val persisted = app.getSharedPreferences("settings", Context.MODE_PRIVATE)
            .getString("language_tag", SYSTEM) ?: SYSTEM
        selectedTag = persisted
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val manager = app.getSystemService(LocaleManager::class.java)
            val installed = manager?.applicationLocales
            if (installed != null && !installed.isEmpty) {
                val tag = installed.toLanguageTags().split(",").firstOrNull().orEmpty()
                if (tag in supportedTags) selectedTag = tag
            }
        }
        applyInMemory(app, selectedTag)
    }

    fun setLanguage(context: Context, tag: String) {
        val normalized = normalizeSelection(tag)
        context.applicationContext
            .getSharedPreferences("settings", Context.MODE_PRIVATE)
            .edit()
            .putString("language_tag", normalized)
            .apply()
        selectedTag = normalized
        applyInMemory(context.applicationContext, normalized)
    }

    /** Persist, apply, and recreate so Compose and resources pick up the change. */
    fun applyToActivity(activity: Activity, tag: String) {
        val normalized = normalizeSelection(tag)
        setLanguage(activity, normalized)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val manager = activity.getSystemService(LocaleManager::class.java)
            manager?.applicationLocales = if (normalized == SYSTEM) {
                LocaleList.getEmptyLocaleList()
            } else {
                LocaleList.forLanguageTags(normalized)
            }
        }
        activity.recreate()
    }

    /** Find the hosting activity from a (possibly wrapped) Compose context. */
    fun applyFrom(context: Context, tag: String) {
        var current: Context? = context
        while (current is ContextWrapper) {
            if (current is Activity) {
                applyToActivity(current, tag)
                return
            }
            current = current.baseContext
        }
        setLanguage(context, tag)
    }

    fun currentLocale(): Locale = Locale.forLanguageTag(activeTag)

    fun activeLanguageTag(): String = activeTag

    /** Apply the selected language to an activity base context (API 24+). */
    fun wrap(context: Context): Context {
        val tag = effectiveTag(selectedTag)
        val config = Configuration(context.resources.configuration)
        config.setLocale(Locale.forLanguageTag(tag))
        return context.createConfigurationContext(config)
    }

    fun tr(source: String, params: Map<String, Any?> = emptyMap()): String {
        val value = table[source]
        if (value == null) return format(source, params)
        return format(selectPlural(value, params), params)
    }

    fun tr(source: String, vararg params: Pair<String, Any?>): String =
        tr(source, params.toMap())

    fun resolve(tag: String, systemTags: List<String>): String {
        if (tag in supportedTags) return tag
        for (raw in systemTags) {
            val value = raw.replace('_', '-').lowercase(Locale.ROOT)
            if (value.startsWith("zh")) {
                return if (
                    value.contains("hant") ||
                    value.startsWith("zh-tw") ||
                    value.startsWith("zh-hk") ||
                    value.startsWith("zh-mo")
                ) ZH_TW else ZH_CN
            }
            if (value.startsWith("en")) return EN
            if (value.startsWith("ja")) return JA
        }
        return ZH_CN
    }

    private fun normalizeSelection(tag: String): String =
        if (tag == SYSTEM || tag in supportedTags) tag else SYSTEM

    private fun effectiveTag(tag: String): String = resolve(tag, systemTags())

    private fun systemTags(): List<String> {
        val locales = android.content.res.Resources.getSystem().configuration.locales
        return (0 until locales.size()).map { locales[it].toLanguageTag() }
    }

    private fun applyInMemory(context: Context, tag: String) {
        activeTag = effectiveTag(tag)
        table = if (activeTag == ZH_CN) emptyMap() else load(context, activeTag)
    }

    private fun load(context: Context, tag: String): Map<String, Any> = runCatching {
        val text = context.assets.open("i18n/$tag.json").bufferedReader().use { it.readText() }
        val root = JSONObject(text)
        buildMap {
            val keys = root.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                when (val value = root.get(key)) {
                    is String -> put(key, value)
                    is JSONObject -> {
                        val variants = buildMap {
                            val variantKeys = value.keys()
                            while (variantKeys.hasNext()) {
                                val variant = variantKeys.next()
                                put(variant, value.getString(variant))
                            }
                        }
                        put(key, variants)
                    }
                }
            }
        }
    }.getOrDefault(emptyMap())

    private fun selectPlural(value: Any, params: Map<String, Any?>): String {
        if (value is String) return value
        if (value is Map<*, *>) {
            val count = params.values.filterIsInstance<Number>().firstOrNull()?.toInt()
            val key = if (count == 1) "one" else "other"
            return value[key] as? String ?: value["other"] as? String ?: value["one"] as? String ?: ""
        }
        return value.toString()
    }

    private fun format(source: String, params: Map<String, Any?>): String =
        placeholder.replace(source) { match ->
            val key = match.groupValues[1]
            params[key]?.toString() ?: match.value
        }
}
