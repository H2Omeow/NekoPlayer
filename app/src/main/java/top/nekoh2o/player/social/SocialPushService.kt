package top.nekoh2o.player.social

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import top.nekoh2o.player.AppVisibility
import top.nekoh2o.player.MainActivity
import top.nekoh2o.player.R
import top.nekoh2o.player.data.net.CookieStore
import top.nekoh2o.player.data.social.SocialMessageEvent
import top.nekoh2o.player.data.social.SocialSseConnection

/** 常驻的社区消息 SSE 服务：只在登录期间运行，SSE 断线指数退避重连。 */
class SocialPushService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }
    private var loopJob: Job? = null
    @Volatile private var connection: SocialSseConnection? = null

    override fun onCreate() {
        super.onCreate()
        SocialNotifications.ensureChannels(this)
        startForeground(SERVICE_ID, SocialNotifications.serviceNotification(this))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        startLoop()
        return START_STICKY
    }

    private fun startLoop() {
        if (loopJob?.isActive == true) return
        loopJob = scope.launch {
            var attempt = 0
            while (isActive) {
                CookieStore.awaitReady()
                if (CookieStore.appTokenValue().isEmpty()) {
                    stopSelf()
                    return@launch
                }
                val sse = try {
                    SocialSseConnection.open()
                } catch (e: Exception) {
                    delay(backoff(attempt++))
                    continue
                }
                connection = sse
                try {
                    sse.read { event, data ->
                        if (event == "ready") {
                            attempt = 0
                            return@read
                        }
                        if (event == "message") handleMessage(data)
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // 断线重连
                } finally {
                    sse.close()
                    connection = null
                }
                if (!isActive) break
                delay(backoff(attempt++))
            }
        }
    }

    private fun handleMessage(data: String) {
        if (AppVisibility.foreground) return
        val event = runCatching { json.decodeFromString<SocialMessageEvent>(data) }.getOrNull() ?: return
        val message = event.message ?: return
        if (message.owned) return
        val sender = message.sender?.displayName ?: tr("新消息")
        val text = when {
            message.deleted -> return
            message.kind == "song" -> tr("[歌曲] {title}", "title" to (message.song?.nm ?: tr("分享")))
            message.text.isNotBlank() -> message.text
            else -> tr("发来一条消息")
        }
        val target = "nekoplayer://chat?peer=" + Uri.encode(event.peerId.ifBlank { message.senderId })
        SocialNotifications.showMessage(this, message.id, sender, text, target)
    }

    private fun backoff(attempt: Int): Long = (1000L shl attempt.coerceIn(0, 6)).coerceAtMost(60_000L)

    override fun onDestroy() {
        connection?.close()
        connection = null
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val SERVICE_ID = 4102
        const val ACTION_STOP = "top.nekoh2o.player.social.STOP"

        fun start(context: Context) {
            val intent = Intent(context, SocialPushService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // Android 12+ 在后台启动前台服务会抛异常；下一次回到前台再试。
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SocialPushService::class.java))
        }
    }
}

object SocialNotifications {
    private const val CHANNEL_SERVICE = "social_service"
    private const val CHANNEL_MESSAGES = "social_messages"
    private const val SERVICE_NOTIFICATION_ID = 4102

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_SERVICE, tr("社区后台连接"), NotificationManager.IMPORTANCE_MIN).apply {
                description = tr("保持社区私信实时连接")
                setShowBadge(false)
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_MESSAGES, tr("社区消息"), NotificationManager.IMPORTANCE_HIGH).apply {
                description = tr("私信和新粉丝通知")
            }
        )
    }

    fun serviceNotification(context: Context): android.app.Notification {
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                data = Uri.parse("nekoplayer://chat")
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(context, CHANNEL_SERVICE)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(tr("NekoPlayer 社区"))
            .setContentText(tr("私信实时连接已开启"))
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(open)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
    }

    fun showMessage(context: Context, messageId: String, title: String, text: String, deepLink: String) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            data = Uri.parse(deepLink)
        }
        val pending = PendingIntent.getActivity(
            context,
            messageId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_MESSAGES)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        try {
            NotificationManagerCompat.from(context)
                .notify(messageId.hashCode() and 0x7fffffff, notification)
        } catch (e: SecurityException) {
            // 用户拒绝通知权限时仍保持后台连接。
        }
    }
}
