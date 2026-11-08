package top.nekoh2o.player.i18n

import org.junit.Assert.assertEquals
import org.junit.Test

class NekoI18nTest {
    @Test
    fun explicitTagsWin() {
        assertEquals(NekoI18n.EN, NekoI18n.resolve(NekoI18n.EN, listOf("zh-TW")))
        assertEquals(NekoI18n.JA, NekoI18n.resolve(NekoI18n.JA, listOf("en-US")))
    }

    @Test
    fun chineseScriptsMapToTraditional() {
        assertEquals(NekoI18n.ZH_TW, NekoI18n.resolve(NekoI18n.SYSTEM, listOf("zh-Hant-TW")))
        assertEquals(NekoI18n.ZH_TW, NekoI18n.resolve(NekoI18n.SYSTEM, listOf("zh_HK")))
        assertEquals(NekoI18n.ZH_CN, NekoI18n.resolve(NekoI18n.SYSTEM, listOf("zh-CN")))
    }

    @Test
    fun otherLanguagesFallBackToSimplifiedChinese() {
        assertEquals(NekoI18n.EN, NekoI18n.resolve(NekoI18n.SYSTEM, listOf("en-GB")))
        assertEquals(NekoI18n.JA, NekoI18n.resolve(NekoI18n.SYSTEM, listOf("ja-JP")))
        assertEquals(NekoI18n.ZH_CN, NekoI18n.resolve(NekoI18n.SYSTEM, listOf("fr-FR")))
    }

    @Test
    fun missingTableKeepsSourceAndSubstitutesPlaceholders() {
        assertEquals("共 3 首", NekoI18n.tr("共 {count} 首", "count" to 3))
    }
}
