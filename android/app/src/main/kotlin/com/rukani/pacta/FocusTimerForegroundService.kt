package com.rukani.pacta

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.util.Locale

/**
 * 专注 / 预约准备的常驻进度前台服务。
 *
 * 计时只在主线程 Handler 上推进：每秒唤醒一次本进程刷新同一张通知，因此进度
 * 条与倒计时不会和后台任务抢一份状态，也不需要额外的 WakeLock。到达结束时刻
 * 或收到 [ACTION_STOP] 时立即撤下通知并结束服务。
 */
class FocusTimerForegroundService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var request: FocusTimerRequest? = null
    private var foregroundStarted = false

    private val ticker = object : Runnable {
        override fun run() {
            val current = request ?: return
            if (System.currentTimeMillis() >= current.endsAtMs) {
                stopTimer()
                return
            }
            post(current)
            handler.postDelayed(this, TICK_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val incoming = FocusTimerRequest.from(intent) ?: return START_NOT_STICKY
        ensureChannel()
        if (incoming.action == ACTION_STOP) {
            // 冷启动的 STOP（例如登出时服务还没起来）同样走 startForegroundService，
            // 所以必须先进入前台状态再立刻退出，否则系统会判定前台服务超时崩溃。
            if (!foregroundStarted) {
                foregroundStarted = enterForeground(incoming)
            }
            stopTimer()
            return START_NOT_STICKY
        }

        request = incoming
        foregroundStarted = enterForeground(incoming)
        post(incoming)
        handler.removeCallbacks(ticker)
        handler.postDelayed(ticker, TICK_INTERVAL_MS)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        request = null
        // 服务被系统或 stopService 直接销毁时也要撤下通知，否则它永远留在状态栏。
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        foregroundStarted = false
        markRunning(false)
        super.onDestroy()
    }

    private fun enterForeground(incoming: FocusTimerRequest): Boolean {
        val notification = buildNotification(incoming)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        return try {
            ServiceCompat.startForeground(this, incoming.notificationId, notification, type)
            markRunning(true)
            true
        } catch (error: Exception) {
            // 系统拒绝进入前台状态时，静默结束服务比崩溃更安全；调用方已经收到
            // 自己的回退路径（静态进度通知）。
            markRunning(false)
            stopSelf()
            false
        }
    }

    private fun post(current: FocusTimerRequest) {
        val notification = buildNotification(current)
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(current.notificationId, notification)
    }

    private fun stopTimer() {
        handler.removeCallbacksAndMessages(null)
        request = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        foregroundStarted = false
        markRunning(false)
        stopSelf()
    }

    private fun buildNotification(current: FocusTimerRequest): Notification {
        val now = System.currentTimeMillis()
        val maxProgress = if (current.totalSeconds > 0) current.totalSeconds else 1
        val elapsedSeconds = ((now - current.startedAtMs) / 1000L).coerceAtLeast(0L)
        val progress = elapsedSeconds.coerceAtMost(maxProgress.toLong()).toInt()
        val remainingSeconds = ((current.endsAtMs - now) / 1000L).coerceAtLeast(0L)
        val clock = formatClock(remainingSeconds)
        val title = if (current.titlePrefix.isBlank()) {
            "剩余 $clock"
        } else {
            "${current.titlePrefix} · 剩余 $clock"
        }
        val body = listOf(current.taskTitle, current.modeLabel)
            .filter { it.isNotBlank() }
            .joinToString(" · ")
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.pacta_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setProgress(maxProgress, progress, false)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setShowWhen(true)
            .setWhen(current.endsAtMs)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(contentIntent(current.payload))
            .build()
    }

    /// 点按通知回到进行中的会话；Dart 侧按 payload 打开同一会话。
    private fun contentIntent(payload: String): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_PAYLOAD, payload)
        }
        // Android 12 起 PendingIntent 必须显式声明可变性；点按只读负载，用不可变。
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(this, CONTENT_REQUEST_CODE, intent, flags)
    }

    /// 与 Dart 侧 `pacta_focus_status_v2` 保持同一语义：可见、无声、不震动。
    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "专注状态",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "显示正在进行的预约或专注倒计时。"
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun formatClock(totalSeconds: Long): String {
        val bounded = totalSeconds.coerceIn(0L, MAX_CLOCK_SECONDS)
        val minutes = bounded / 60L
        val seconds = bounded % 60L
        return String.format(Locale.US, "%02d:%02d", minutes, seconds)
    }

    private data class FocusTimerRequest(
        val action: String,
        val notificationId: Int,
        val titlePrefix: String,
        val taskTitle: String,
        val modeLabel: String,
        val startedAtMs: Long,
        val endsAtMs: Long,
        val totalSeconds: Int,
        val payload: String,
    ) {
        companion object {
            fun from(intent: Intent?): FocusTimerRequest? {
                if (intent == null) return null
                val now = System.currentTimeMillis()
                return FocusTimerRequest(
                    action = intent.action ?: ACTION_START,
                    notificationId = intent.getIntExtra(
                        EXTRA_NOTIFICATION_ID,
                        DEFAULT_NOTIFICATION_ID,
                    ),
                    titlePrefix = intent.getStringExtra(EXTRA_TITLE_PREFIX).orEmpty(),
                    taskTitle = intent.getStringExtra(EXTRA_TASK_TITLE).orEmpty(),
                    modeLabel = intent.getStringExtra(EXTRA_MODE_LABEL).orEmpty(),
                    startedAtMs = intent.getLongExtra(EXTRA_STARTED_AT_MS, now),
                    endsAtMs = intent.getLongExtra(EXTRA_ENDS_AT_MS, now),
                    totalSeconds = intent.getIntExtra(EXTRA_TOTAL_SECONDS, 0),
                    payload = intent.getStringExtra(EXTRA_PAYLOAD).orEmpty(),
                )
            }
        }
    }

    companion object {
        const val ACTION_START = "START"
        const val ACTION_UPDATE = "UPDATE"
        const val ACTION_STOP = "STOP"

        const val CHANNEL_ID = "pacta_focus_status_v2"
        const val DEFAULT_NOTIFICATION_ID = 2200

        const val EXTRA_NOTIFICATION_ID = "notificationId"
        const val EXTRA_TITLE_PREFIX = "titlePrefix"
        const val EXTRA_TASK_TITLE = "taskTitle"
        const val EXTRA_MODE_LABEL = "modeLabel"
        const val EXTRA_STARTED_AT_MS = "startedAtMs"
        const val EXTRA_ENDS_AT_MS = "endsAtMs"
        const val EXTRA_TOTAL_SECONDS = "totalSeconds"

        /// MainActivity 读取它，把点按事件交回 Dart。
        const val EXTRA_PAYLOAD = "pacta_notification_payload"

        private const val TICK_INTERVAL_MS = 1000L
        private const val CONTENT_REQUEST_CODE = 2200
        private const val MAX_CLOCK_SECONDS = 24L * 60L * 60L

        @Volatile
        private var runningState: Boolean = false

        /// 进程内是否真的有一个前台计时服务在跑。
        ///
        /// 只用于回答"现在停止是不是空操作"：没有服务时绝不能为了发送 STOP 而
        /// 冷启动一个前台服务，否则每次启动应用都会闪一下通知。
        val running: Boolean
            get() = runningState

        /// 生命周期钩子回写运行状态；MainActivity 只读 [running]。
        fun markRunning(value: Boolean) {
            runningState = value
        }
    }
}
