package top.nekoh2o.player.data.plugins

/**
 * Playback headers required by the built-in aggregation service.
 *
 * Bilibili returns DASH audio through an EdgeOne-protected proxy. A plain GET
 * without a Range header gets an HTML block page instead of audio; ExoPlayer
 * does not send Range for its initial open, so the header must be supplied
 * explicitly. The referer and browser user agent keep the CDN request
 * compatible; players replace Range with their own when seeking.
 */
internal object GatewayPlaybackHeaders {
    private val bilibili = mapOf(
        "Referer" to "https://www.bilibili.com/",
        "User-Agent" to
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Range" to "bytes=0-",
    )

    fun forPlatform(platform: String): Map<String, String> =
        if (platform == "bilibili") bilibili else emptyMap()
}
