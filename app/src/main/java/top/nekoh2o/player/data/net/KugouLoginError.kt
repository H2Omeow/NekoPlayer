package top.nekoh2o.player.data.net

import top.nekoh2o.player.i18n.NekoI18n.tr

/** Keep account details and request URLs out of user-visible transport errors. */
fun kugouLoginError(error: Exception): String = when (error) {
    is KugouApiException, is IllegalArgumentException -> error.message ?: tr("登录失败，请重试")
    is javax.net.ssl.SSLException -> tr("酷狗安全连接失败，请检查设备日期或更新应用后重试")
    is java.net.UnknownHostException -> tr("无法解析酷狗服务器地址，请检查网络或 DNS 后重试")
    is java.net.SocketTimeoutException -> tr("酷狗请求超时，请稍后重试")
    is java.io.IOException -> tr("无法连接酷狗服务，请检查网络后重试")
    else -> tr("酷狗响应异常，请稍后重试")
}
