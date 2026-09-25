package com.pacta.pacta

import android.Manifest
import android.content.pm.PackageManager
import android.database.Cursor
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "com.pacta/calendar"
    private val permissionRequestCode = 4720
    private val calendarExecutor = Executors.newSingleThreadExecutor()
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissionStatus" -> result.success(permissionStatus())
                    "requestPermission" -> requestCalendarPermission(result)
                    "listCalendars" -> runCalendarQuery(result) { listCalendars() }
                    "readEvents" -> {
                        val arguments = call.arguments as? Map<*, *>
                        if (arguments == null) {
                            result.error("invalid-arguments", "日历查询参数无效。", null)
                        } else {
                            runCalendarQuery(result) { readEvents(arguments) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun permissionStatus(): String =
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_CALENDAR,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            "granted"
        } else {
            "denied"
        }

    private fun requestCalendarPermission(result: MethodChannel.Result) {
        if (permissionStatus() == "granted") {
            result.success("granted")
            return
        }
        if (permissionResult != null) {
            result.error("permission-request-active", "日历权限请求正在进行。", null)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_CALENDAR),
            permissionRequestCode,
        )
    }

    @Deprecated("Deprecated in Android API")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val pendingResult = permissionResult ?: return
        permissionResult = null
        pendingResult.success(permissionStatus())
    }

    private fun <T> runCalendarQuery(
        result: MethodChannel.Result,
        query: () -> T,
    ) {
        if (permissionStatus() != "granted") {
            result.error("calendar-permission-denied", "尚未获得读取日历权限。", null)
            return
        }
        calendarExecutor.execute {
            try {
                val value = query()
                runOnUiThread { result.success(value) }
            } catch (error: SecurityException) {
                runOnUiThread {
                    result.error("calendar-permission-denied", "尚未获得读取日历权限。", null)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("calendar-read-failed", "系统日历暂时无法读取。", null)
                }
            }
        }
    }

    private fun listCalendars(): List<Map<String, Any?>> {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE,
            CalendarContract.Calendars.OWNER_ACCOUNT,
            CalendarContract.Calendars.CALENDAR_TIME_ZONE,
        )
        val sources = mutableListOf<Map<String, Any?>>()
        val cursor = contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            "${CalendarContract.Calendars.VISIBLE} = ?",
            arrayOf("1"),
            "${CalendarContract.Calendars.CALENDAR_DISPLAY_NAME} COLLATE NOCASE",
        ) ?: error("系统日历列表查询未返回结果。")

        cursor.use {
            while (it.moveToNext()) {
                val localId = it.getLong(it.getColumnIndexOrThrow(CalendarContract.Calendars._ID))
                val displayName = it.stringOrNull(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
                    ?.takeIf(String::isNotBlank) ?: "未命名日历"
                val internalName = it.stringOrNull(CalendarContract.Calendars.NAME).orEmpty()
                val accountName = it.stringOrNull(CalendarContract.Calendars.ACCOUNT_NAME).orEmpty()
                val accountType = it.stringOrNull(CalendarContract.Calendars.ACCOUNT_TYPE).orEmpty()
                val ownerAccount = it.stringOrNull(CalendarContract.Calendars.OWNER_ACCOUNT).orEmpty()
                val identity = if (accountType.isBlank() && accountName.isBlank() && ownerAccount.isBlank()) {
                    "local|$localId|$internalName"
                } else {
                    listOf(accountType, ownerAccount, accountName, internalName)
                        .joinToString("\u001f")
                }
                sources.add(
                    mapOf(
                        "sourceId" to stableIdentifier(identity),
                        "displayName" to displayName,
                        "timeZoneId" to (it.stringOrNull(CalendarContract.Calendars.CALENDAR_TIME_ZONE)
                            ?: "Etc/UTC"),
                        "localCalendarId" to localId.toString(),
                    ),
                )
            }
        }
        return sources
    }

    private fun readEvents(arguments: Map<*, *>): List<Map<String, Any?>> {
        val calendarIds = (arguments["calendarIds"] as? List<*>)
            ?.mapNotNull { (it as? Number)?.toLong() }
            ?.toSet()
            .orEmpty()
        val begin = (arguments["from"] as? Number)?.toLong() ?: return emptyList()
        val end = (arguments["to"] as? Number)?.toLong() ?: return emptyList()
        if (calendarIds.isEmpty() || end <= begin) return emptyList()

        val sourcesByLocalId = listCalendars().associateBy { it["localCalendarId"] as String }
        val placeholders = calendarIds.joinToString(",") { "?" }
        val instanceUri = CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(begin.toString())
            .appendPath(end.toString())
            .build()
        val instanceProjection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.CALENDAR_ID,
        )
        val instanceRows = mutableListOf<InstanceRow>()
        val instanceCursor = contentResolver.query(
            instanceUri,
            instanceProjection,
            "${CalendarContract.Instances.CALENDAR_ID} IN ($placeholders)",
            calendarIds.map(Long::toString).toTypedArray(),
            "${CalendarContract.Instances.BEGIN} ASC",
        ) ?: error("系统日历活动查询未返回结果。")
        instanceCursor.use { cursor ->
            while (cursor.moveToNext()) {
                instanceRows.add(
                    InstanceRow(
                        eventId = cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_ID)),
                        startsAt = cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN)),
                        endsAt = cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Instances.END)),
                        calendarId = cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Instances.CALENDAR_ID)),
                    ),
                )
            }
        }

        val eventRows = queryEventDetails(instanceRows.map { it.eventId }.toSet())
        val output = mutableListOf<Map<String, Any?>>()
        for (instance in instanceRows) {
            val source = sourcesByLocalId[instance.calendarId.toString()] ?: continue
            val event = eventRows[instance.eventId] ?: continue
            if (event.status == CalendarContract.Events.STATUS_CANCELED ||
                instance.endsAt <= instance.startsAt
            ) {
                continue
            }
            val externalId = event.originalSyncId
                ?: event.syncId
                ?: event.uid
                ?: "local:${instance.eventId}"
            val occurrenceStart = event.originalInstanceTime ?: instance.startsAt
            val occurrenceId = "$externalId@$occurrenceStart"
            val eventIdentity = "$externalId@$occurrenceStart"
            val allDay = event.allDay
            output.add(
                mapOf(
                    "sourceId" to source["sourceId"],
                    "sourceEventId" to externalId,
                    "occurrenceId" to occurrenceId,
                    "eventIdentity" to eventIdentity,
                    "title" to event.title,
                    "startsAt" to instance.startsAt,
                    "endsAt" to instance.endsAt,
                    "allDay" to allDay,
                    "allDayStartDate" to if (allDay) utcDateKey(instance.startsAt) else null,
                    "allDayEndDateExclusive" to if (allDay) utcDateKey(instance.endsAt) else null,
                    "availability" to availabilityName(event.availability),
                    "timeZoneId" to event.timeZoneId.ifBlank {
                        sourcesByLocalId[instance.calendarId.toString()]?.get("timeZoneId") as? String ?: "Etc/UTC"
                    },
                ),
            )
        }
        return output
    }

    private fun queryEventDetails(eventIds: Set<Long>): Map<Long, EventRow> {
        if (eventIds.isEmpty()) return emptyMap()
        val output = mutableMapOf<Long, EventRow>()
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.ALL_DAY,
            CalendarContract.Events.AVAILABILITY,
            CalendarContract.Events.EVENT_TIMEZONE,
            CalendarContract.Events._SYNC_ID,
            CalendarContract.Events.ORIGINAL_SYNC_ID,
            CalendarContract.Events.ORIGINAL_INSTANCE_TIME,
            CalendarContract.Events.UID_2445,
            CalendarContract.Events.STATUS,
        )
        for (chunk in eventIds.toList().chunked(400)) {
            val placeholders = chunk.joinToString(",") { "?" }
            val eventCursor = contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                projection,
                "${CalendarContract.Events._ID} IN ($placeholders)",
                chunk.map(Long::toString).toTypedArray(),
                null,
            ) ?: error("系统日历活动详情查询未返回结果。")
            eventCursor.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Events._ID))
                    output[id] = EventRow(
                        title = cursor.stringOrNull(CalendarContract.Events.TITLE) ?: "",
                        allDay = cursor.getInt(cursor.getColumnIndexOrThrow(CalendarContract.Events.ALL_DAY)) != 0,
                        availability = cursor.intOrNull(CalendarContract.Events.AVAILABILITY),
                        timeZoneId = cursor.stringOrNull(CalendarContract.Events.EVENT_TIMEZONE).orEmpty(),
                        syncId = cursor.stringOrNull(CalendarContract.Events._SYNC_ID),
                        originalSyncId = cursor.stringOrNull(CalendarContract.Events.ORIGINAL_SYNC_ID),
                        originalInstanceTime = cursor.longOrNull(CalendarContract.Events.ORIGINAL_INSTANCE_TIME),
                        uid = cursor.stringOrNull(CalendarContract.Events.UID_2445),
                        status = cursor.intOrNull(CalendarContract.Events.STATUS),
                    )
                }
            }
        }
        return output
    }

    private fun availabilityName(value: Int?): String = when (value) {
        CalendarContract.Events.AVAILABILITY_FREE -> "free"
        CalendarContract.Events.AVAILABILITY_BUSY -> "busy"
        CalendarContract.Events.AVAILABILITY_TENTATIVE -> "tentative"
        else -> "unknown"
    }

    private fun stableIdentifier(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun utcDateKey(milliseconds: Long): String {
        val date = java.time.Instant.ofEpochMilli(milliseconds)
            .atZone(java.time.ZoneOffset.UTC)
            .toLocalDate()
        return date.toString()
    }

    override fun onDestroy() {
        calendarExecutor.shutdown()
        super.onDestroy()
    }

    private fun Cursor.stringOrNull(column: String): String? {
        val index = getColumnIndex(column)
        return if (index < 0 || isNull(index)) null else getString(index)
    }

    private fun Cursor.longOrNull(column: String): Long? {
        val index = getColumnIndex(column)
        return if (index < 0 || isNull(index)) null else getLong(index)
    }

    private fun Cursor.intOrNull(column: String): Int? {
        val index = getColumnIndex(column)
        return if (index < 0 || isNull(index)) null else getInt(index)
    }

    private data class InstanceRow(
        val eventId: Long,
        val startsAt: Long,
        val endsAt: Long,
        val calendarId: Long,
    )

    private data class EventRow(
        val title: String,
        val allDay: Boolean,
        val availability: Int?,
        val timeZoneId: String,
        val syncId: String?,
        val originalSyncId: String?,
        val originalInstanceTime: Long?,
        val uid: String?,
        val status: Int?,
    )
}
