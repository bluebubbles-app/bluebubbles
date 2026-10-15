package io.github.bluebubblesapp.bluebubbles

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.role.RoleManager
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.provider.BaseColumns
import android.provider.ContactsContract
import android.provider.Settings
import android.provider.Telephony
import android.telephony.SmsManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "bluebubbles/sms"
        private const val TAG = "BlueBubblesSms"
        private const val NATIVE_BUILD = "2026-10-16-compose-and-contacts-v1"
        private const val ROLE_REQUEST = 4701
        private const val PERMISSION_REQUEST = 4702
        private const val PROVIDER_LOAD_TIMEOUT_MS = 20_000L
        private const val METHOD_REPLY_TIMEOUT_MS = 30_000L
    }

    private lateinit var channel: MethodChannel
    private var pendingRoleResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationThreadId: String? = null
    private var observerRegistered = false
    @Volatile private var lastLoadStage = "Not started"
    @Volatile private var lastLoadResult = "No load attempted"
    @Volatile private var lastLoadDurationMs = 0L
    @Volatile private var lastThreadLoad = "Not started"
    @Volatile private var suppressProviderReloadUntil = 0L
    private val enrichmentGeneration = AtomicInteger(0)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val notifyMessagesChanged = Runnable {
        if (::channel.isInitialized) channel.invokeMethod("messagesChanged", null)
    }
    private val smsObserver = object : ContentObserver(mainHandler) {
        override fun onChange(selfChange: Boolean) {
            if (SystemClock.elapsedRealtime() < suppressProviderReloadUntil) {
                return
            }
            mainHandler.removeCallbacks(notifyMessagesChanged)
            mainHandler.postDelayed(notifyMessagesChanged, 250)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingNotificationThreadId = notificationThreadId(intent)
        pendingNotificationThreadId?.let {
            Log.i(TAG, "Cold notification open for thread $it")
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val threadId = notificationThreadId(intent) ?: return
        Log.i(TAG, "Notification open for thread $threadId")
        pendingNotificationThreadId = threadId
        if (::channel.isInitialized) {
            channel.invokeMethod("notificationOpened", threadId)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i(TAG, "Native SMS bridge $NATIVE_BUILD")
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        )
        channel.setMethodCallHandler(::handleMethodCall)
        contentResolver.registerContentObserver(
            Telephony.Sms.CONTENT_URI,
            true,
            smsObserver,
        )
        contentResolver.registerContentObserver(
            Telephony.Mms.CONTENT_URI,
            true,
            smsObserver,
        )
        observerRegistered = true
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> result.success(currentState())
            "consumeNotificationThread" -> {
                result.success(pendingNotificationThreadId)
                pendingNotificationThreadId = null
            }
            "requestDefaultSmsRole" -> requestDefaultSmsRole(result)
            "requestSmsPermissions" -> requestSmsPermissions(result)
            "loadConversations" -> loadConversations(result)
            "loadThreadMessages" -> loadThreadMessages(call, result)
            "getSmsMessageCount" -> getSmsMessageCount(result)
            "resolveOrCreateConversation" -> resolveOrCreateConversation(call, result)
            "searchContacts" -> searchContacts(call, result)
            "sendSms" -> sendSms(call, result)
            "markThreadRead" -> markThreadRead(call, result)
            "deleteThread" -> deleteThread(call, result)
            "dialNumber" -> dialNumber(call, result)
            "openContact" -> openContact(call, result)
            "getDiagnostics" -> getDiagnostics(result)
            "openDefaultSmsSettings" -> {
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
                } else {
                    Intent(Settings.ACTION_SETTINGS)
                }
                startActivity(intent)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun notificationThreadId(intent: Intent?): String? =
        intent?.getStringExtra(MessageNotifier.EXTRA_THREAD_ID)
            ?.takeIf { it.isNotBlank() }

    private fun currentState(): Map<String, Boolean> = mapOf(
        "supported" to isSmsRoleAvailable(),
        "isDefaultSmsApp" to isDefaultSmsApp(),
        "permissionsGranted" to hasCoreSmsPermissions(),
        "contactsGranted" to hasPermission(Manifest.permission.READ_CONTACTS),
        "notificationsGranted" to notificationsGranted(),
    )

    private fun notificationsGranted(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            hasPermission(Manifest.permission.POST_NOTIFICATIONS)

    private fun hasPermission(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun isSmsRoleAvailable(): Boolean {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)) {
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return getSystemService(RoleManager::class.java)
            .isRoleAvailable(RoleManager.ROLE_SMS)
    }

    private fun isDefaultSmsApp(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return getSystemService(RoleManager::class.java)
                .isRoleHeld(RoleManager.ROLE_SMS)
        }
        return Telephony.Sms.getDefaultSmsPackage(this) == packageName
    }

    private fun hasCoreSmsPermissions(): Boolean {
        val permissions = arrayOf(
            Manifest.permission.READ_SMS,
            Manifest.permission.SEND_SMS,
            Manifest.permission.RECEIVE_SMS,
        )
        return permissions.all(::hasPermission)
    }

    private fun requestDefaultSmsRole(result: MethodChannel.Result) {
        if (!isSmsRoleAvailable()) {
            result.error("sms_unavailable", "SMS is not available on this device.", null)
            return
        }
        if (isDefaultSmsApp()) {
            result.success(true)
            return
        }
        if (pendingRoleResult != null) {
            result.error("request_active", "An SMS role request is already active.", null)
            return
        }
        pendingRoleResult = result
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            getSystemService(RoleManager::class.java)
                .createRequestRoleIntent(RoleManager.ROLE_SMS)
        } else {
            Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT).apply {
                putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, packageName)
            }
        }
        startActivityForResult(intent, ROLE_REQUEST)
    }

    private fun requestSmsPermissions(result: MethodChannel.Result) {
        if (!isDefaultSmsApp()) {
            result.error(
                "not_default_sms",
                "BlueBubbles must be the default SMS app before requesting SMS permissions.",
                null,
            )
            return
        }
        if (pendingPermissionResult != null) {
            result.error("request_active", "A permission request is already active.", null)
            return
        }
        val permissions = mutableListOf(
            Manifest.permission.READ_SMS,
            Manifest.permission.SEND_SMS,
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.RECEIVE_MMS,
            Manifest.permission.RECEIVE_WAP_PUSH,
            Manifest.permission.READ_CONTACTS,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        val missingPermissions = permissions.filterNot(::hasPermission)
        if (missingPermissions.isEmpty()) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        requestPermissions(missingPermissions.toTypedArray(), PERMISSION_REQUEST)
    }

    private fun loadConversations(result: MethodChannel.Result) {
        if (!isDefaultSmsApp() || !hasCoreSmsPermissions()) {
            result.error(
                "sms_access_denied",
                "BlueBubbles needs the default SMS role and SMS permissions.",
                null,
            )
            return
        }
        val replied = AtomicBoolean(false)
        val timeoutReply = Runnable {
            if (replied.compareAndSet(false, true)) {
                lastLoadDurationMs = METHOD_REPLY_TIMEOUT_MS
                lastLoadResult = "Timed out while $lastLoadStage"
                Log.e(TAG, lastLoadResult)
                result.error(
                    "sms_query_timeout",
                    lastLoadResult,
                    null,
                )
            }
        }
        mainHandler.postDelayed(timeoutReply, METHOD_REPLY_TIMEOUT_MS)
        Thread {
            val startedAt = SystemClock.elapsedRealtime()
            try {
                lastLoadStage = "Reading SMS provider"
                lastLoadResult = "In progress"
                Log.i(TAG, "Conversation load started ($NATIVE_BUILD)")
                val page = querySmsConversations()
                val conversations = page.items
                val duration = SystemClock.elapsedRealtime() - startedAt
                runOnUiThread {
                    if (replied.compareAndSet(false, true)) {
                        mainHandler.removeCallbacks(timeoutReply)
                        lastLoadDurationMs = duration
                        lastLoadStage = "Completed"
                        lastLoadResult = "${conversations.size} conversations"
                        Log.i(
                            TAG,
                            "Conversation load completed: ${conversations.size} " +
                                "rows in $lastLoadDurationMs ms",
                        )
                        result.success(conversations)
                        enrichConversationSummaries(
                            page.summaries,
                            enrichmentGeneration.incrementAndGet(),
                        )
                    }
                }
            } catch (error: Exception) {
                val duration = SystemClock.elapsedRealtime() - startedAt
                runOnUiThread {
                    if (replied.compareAndSet(false, true)) {
                        mainHandler.removeCallbacks(timeoutReply)
                        lastLoadDurationMs = duration
                        lastLoadResult =
                            "${error.javaClass.simpleName}: ${error.message}"
                        Log.e(
                            TAG,
                            "Conversation load failed at $lastLoadStage after " +
                                "$lastLoadDurationMs ms",
                            error,
                        )
                        result.error(
                            "sms_query_failed",
                            "$lastLoadStage: $lastLoadResult",
                            null,
                        )
                    }
                }
            }
        }.start()
    }

    private fun dialNumber(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address")?.trim().orEmpty()
        if (address.isEmpty()) {
            result.error("invalid_number", "A phone number is required.", null)
            return
        }
        try {
            startActivity(
                Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", address, null)),
            )
            result.success(null)
        } catch (error: Exception) {
            result.error("dial_failed", error.message, null)
        }
    }

    private fun openContact(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address")?.trim().orEmpty()
        if (address.isEmpty()) {
            result.error("invalid_number", "A phone number is required.", null)
            return
        }
        Thread {
            try {
                val filterUri = Uri.withAppendedPath(
                    ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                    Uri.encode(address),
                )
                var contactUri: Uri? = null
                contentResolver.query(
                    filterUri,
                    arrayOf(
                        ContactsContract.PhoneLookup._ID,
                        ContactsContract.PhoneLookup.LOOKUP_KEY,
                    ),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        contactUri = ContactsContract.Contacts.getLookupUri(
                            cursor.getLong(0),
                            cursor.getString(1),
                        )
                    }
                }
                val intent = if (contactUri != null) {
                    Intent(Intent.ACTION_VIEW, contactUri)
                } else {
                    Intent(ContactsContract.Intents.Insert.ACTION).apply {
                        type = ContactsContract.RawContacts.CONTENT_TYPE
                        putExtra(ContactsContract.Intents.Insert.PHONE, address)
                    }
                }
                runOnUiThread {
                    startActivity(intent)
                    result.success(null)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("contact_open_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun getDiagnostics(result: MethodChannel.Result) {
        Thread {
            val diagnostics = linkedMapOf<String, Any?>(
                "Package" to packageName,
                "Native build" to NATIVE_BUILD,
                "Android SDK" to Build.VERSION.SDK_INT,
                "Default SMS role" to isDefaultSmsApp(),
                "Default SMS package" to runCatching {
                    Telephony.Sms.getDefaultSmsPackage(this)
                }.getOrNull(),
                "READ_SMS" to hasPermission(Manifest.permission.READ_SMS),
                "SEND_SMS" to hasPermission(Manifest.permission.SEND_SMS),
                "RECEIVE_SMS" to hasPermission(Manifest.permission.RECEIVE_SMS),
                "READ_CONTACTS" to hasPermission(Manifest.permission.READ_CONTACTS),
                "Notifications" to notificationsGranted(),
                "READ_SMS AppOp" to readSmsAppOp(),
                "Last load stage" to lastLoadStage,
                "Last load result" to lastLoadResult,
                "Last load duration" to "$lastLoadDurationMs ms",
                "Last thread load" to lastThreadLoad,
            )
            runOnUiThread { result.success(diagnostics) }
        }.start()
    }

    private fun readSmsAppOp(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "legacy"
        return runCatching {
            val manager = getSystemService(AppOpsManager::class.java)
            when (
                manager.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_READ_SMS,
                    Process.myUid(),
                    packageName,
                )
            ) {
                AppOpsManager.MODE_ALLOWED -> "allowed"
                AppOpsManager.MODE_IGNORED -> "ignored"
                AppOpsManager.MODE_ERRORED -> "errored"
                AppOpsManager.MODE_DEFAULT -> "default"
                else -> "unknown"
            }
        }.getOrElse { "${it.javaClass.simpleName}: ${it.message}" }
    }

    private fun <T> providerQuery(
        uri: Uri,
        projection: Array<String>,
        selection: String? = null,
        selectionArgs: Array<String>? = null,
        sortOrder: String? = null,
        timeoutMs: Long = PROVIDER_LOAD_TIMEOUT_MS,
        block: (Cursor) -> T,
    ): T? {
        val cancellationSignal = CancellationSignal()
        val cancelQuery = Runnable { cancellationSignal.cancel() }
        mainHandler.postDelayed(cancelQuery, timeoutMs)
        return try {
            contentResolver.query(
                uri,
                projection,
                selection,
                selectionArgs,
                sortOrder,
                cancellationSignal,
            )?.use { cursor -> block(cursor) }
        } finally {
            mainHandler.removeCallbacks(cancelQuery)
        }
    }

    private fun sendSms(call: MethodCall, result: MethodChannel.Result) {
        if (!isDefaultSmsApp() || !hasCoreSmsPermissions()) {
            result.error("sms_access_denied", "SMS access is not active.", null)
            return
        }
        val address = call.argument<String>("address")?.trim().orEmpty()
        val text = call.argument<String>("text")?.trim().orEmpty()
        if (address.isEmpty() || text.isEmpty()) {
            result.error("invalid_sms", "A recipient and message are required.", null)
            return
        }
        Thread {
            try {
                val manager = SmsManager.getDefault()
                val parts = manager.divideMessage(text)
                if (parts.size > 1) {
                    manager.sendMultipartTextMessage(address, null, parts, null, null)
                } else {
                    manager.sendTextMessage(address, null, text, null, null)
                }
                val values = ContentValues().apply {
                    put(Telephony.Sms.ADDRESS, address)
                    put(Telephony.Sms.BODY, text)
                    put(Telephony.Sms.DATE, System.currentTimeMillis())
                    put(Telephony.Sms.READ, 1)
                    put(Telephony.Sms.SEEN, 1)
                }
                val inserted = contentResolver.insert(
                    Telephony.Sms.Sent.CONTENT_URI,
                    values,
                ) ?: error("The SMS provider rejected the sent message.")
                Log.i(TAG, "SMS queued and stored at $inserted")
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                Log.e(TAG, "SMS send failed", error)
                runOnUiThread {
                    result.error("sms_send_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun loadThreadMessages(call: MethodCall, result: MethodChannel.Result) {
        if (!isDefaultSmsApp() || !hasCoreSmsPermissions()) {
            result.error("sms_access_denied", "SMS access is not active.", null)
            return
        }
        val threadId = call.argument<String>("threadId").orEmpty()
        if (threadId.isEmpty()) {
            result.error("invalid_thread", "A thread ID is required.", null)
            return
        }
        val beforeTimestamp = call.argument<Number>("beforeTimestamp")?.toLong()
        val beforeMessageId = call.argument<String>("beforeMessageId")
            ?.toLongOrNull()
        val pageSize = (call.argument<Number>("limit")?.toInt() ?: 40)
            .coerceIn(20, 250)
        val background = call.argument<Boolean>("background") == true
        val replied = AtomicBoolean(false)
        val timeoutReply = Runnable {
            if (replied.compareAndSet(false, true)) {
                lastThreadLoad = "Timed out after $METHOD_REPLY_TIMEOUT_MS ms"
                Log.e(TAG, "Thread $threadId: $lastThreadLoad")
                result.error("thread_query_timeout", lastThreadLoad, null)
            }
        }
        mainHandler.postDelayed(timeoutReply, METHOD_REPLY_TIMEOUT_MS)
        Thread {
            val startedAt = SystemClock.elapsedRealtime()
            try {
                val messages = queryThreadMessages(
                    threadId,
                    beforeTimestamp,
                    beforeMessageId,
                    pageSize,
                )
                val duration = SystemClock.elapsedRealtime() - startedAt
                runOnUiThread {
                    if (replied.compareAndSet(false, true)) {
                        mainHandler.removeCallbacks(timeoutReply)
                        lastThreadLoad =
                            "${messages.size} messages in $duration ms"
                        if (!background) {
                            Log.i(TAG, "Thread $threadId: $lastThreadLoad")
                        }
                        result.success(messages)
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (replied.compareAndSet(false, true)) {
                        mainHandler.removeCallbacks(timeoutReply)
                        lastThreadLoad =
                            "${error.javaClass.simpleName}: ${error.message}"
                        Log.e(TAG, "Thread $threadId load failed", error)
                        result.error(
                            "sms_query_failed",
                            lastThreadLoad,
                            null,
                        )
                    }
                }
            }
        }.start()
    }

    private fun getSmsMessageCount(result: MethodChannel.Result) {
        if (!isDefaultSmsApp() || !hasCoreSmsPermissions()) {
            result.error("sms_access_denied", "SMS access is not active.", null)
            return
        }
        Thread {
            try {
                val count = providerQuery(
                    Telephony.Sms.CONTENT_URI,
                    arrayOf(BaseColumns._ID),
                ) { cursor -> cursor.count } ?: 0
                runOnUiThread { result.success(count) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("sms_count_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun markThreadRead(call: MethodCall, result: MethodChannel.Result) {
        if (!isDefaultSmsApp() || !hasCoreSmsPermissions()) {
            result.error("sms_access_denied", "SMS access is not active.", null)
            return
        }
        val threadId = call.argument<String>("threadId").orEmpty()
        if (threadId.isEmpty()) {
            result.error("invalid_thread", "A thread ID is required.", null)
            return
        }
        val values = ContentValues().apply {
            put(Telephony.Sms.READ, 1)
            put(Telephony.Sms.SEEN, 1)
        }
        Thread {
            try {
                suppressProviderReloadUntil =
                    SystemClock.elapsedRealtime() + 500L
                contentResolver.update(
                    Telephony.Sms.CONTENT_URI,
                    values,
                    "${Telephony.Sms.THREAD_ID} = ? AND " +
                        "(${Telephony.Sms.READ} = 0 OR ${Telephony.Sms.SEEN} = 0)",
                    arrayOf(threadId),
                )
                contentResolver.update(
                    Telephony.Mms.CONTENT_URI,
                    values,
                    "${Telephony.Mms.THREAD_ID} = ? AND " +
                        "(${Telephony.Mms.READ} = 0 OR ${Telephony.Mms.SEEN} = 0)",
                    arrayOf(threadId),
                )
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("sms_update_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun deleteThread(call: MethodCall, result: MethodChannel.Result) {
        if (!isDefaultSmsApp() || !hasCoreSmsPermissions()) {
            result.error("sms_access_denied", "SMS access is not active.", null)
            return
        }
        val threadId = call.argument<String>("threadId").orEmpty()
        if (threadId.isEmpty()) {
            result.error("invalid_thread", "A thread ID is required.", null)
            return
        }
        Thread {
            try {
                contentResolver.delete(
                    Telephony.Sms.CONTENT_URI,
                    "${Telephony.Sms.THREAD_ID} = ?",
                    arrayOf(threadId),
                )
                contentResolver.delete(
                    Telephony.Mms.CONTENT_URI,
                    "${Telephony.Mms.THREAD_ID} = ?",
                    arrayOf(threadId),
                )
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("sms_delete_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun resolveOrCreateConversation(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!isDefaultSmsApp() || !hasCoreSmsPermissions()) {
            result.error("sms_access_denied", "SMS access is not active.", null)
            return
        }
        val address = call.argument<String>("address").orEmpty().trim()
        if (address.isEmpty()) {
            result.error("invalid_address", "A recipient is required.", null)
            return
        }
        Thread {
            try {
                val threadId = Telephony.Threads.getOrCreateThreadId(
                    this,
                    setOf(address),
                )
                val contact = contactDetails(address)
                val conversation = mapOf(
                    "id" to threadId.toString(),
                    "address" to address,
                    "title" to (contact.name?.takeIf { it.isNotBlank() } ?: address),
                    "preview" to "",
                    "updatedAt" to System.currentTimeMillis(),
                    "unreadCount" to 0,
                    "messages" to emptyList<Map<String, Any?>>(),
                    "avatarBytes" to contact.avatarBytes,
                )
                runOnUiThread { result.success(conversation) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "thread_create_failed",
                        error.message ?: "The conversation could not be created.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun searchContacts(call: MethodCall, result: MethodChannel.Result) {
        if (!hasPermission(Manifest.permission.READ_CONTACTS)) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        val query = call.argument<String>("query").orEmpty().trim()
        if (query.isEmpty()) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        Thread {
            try {
                val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
                    .buildUpon()
                    .appendQueryParameter("limit", "30")
                    .build()
                val matches = providerQuery(
                    uri,
                    arrayOf(
                        ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                        ContactsContract.CommonDataKinds.Phone.NUMBER,
                        ContactsContract.CommonDataKinds.Phone.PHOTO_THUMBNAIL_URI,
                    ),
                    "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ? OR " +
                        "${ContactsContract.CommonDataKinds.Phone.NUMBER} LIKE ?",
                    arrayOf("%$query%", "%$query%"),
                    "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} " +
                        "COLLATE NOCASE ASC",
                    timeoutMs = 3_000L,
                ) { cursor ->
                    val contacts = mutableListOf<Map<String, Any?>>()
                    val seenAddresses = mutableSetOf<String>()
                    while (cursor.moveToNext() && contacts.size < 30) {
                        val address = cursor.getString(1).orEmpty().trim()
                        val normalized = address.filter { it.isDigit() || it == '+' }
                        if (address.isEmpty() || !seenAddresses.add(normalized)) continue
                        val avatarBytes = cursor.getString(2)?.let { value ->
                            runCatching {
                                contentResolver.openInputStream(Uri.parse(value))
                                    ?.use { it.readBytes() }
                            }.getOrNull()
                        }
                        contacts.add(
                            mapOf(
                                "name" to cursor.getString(0).orEmpty(),
                                "address" to address,
                                "avatarBytes" to avatarBytes,
                            ),
                        )
                    }
                    contacts
                } ?: emptyList()
                runOnUiThread { result.success(matches) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "contact_search_failed",
                        error.message ?: "Contacts could not be searched.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun querySmsConversations(): ConversationPage {
        lastLoadStage = "Reading thread summaries"
        val projection = arrayOf(
            BaseColumns._ID,
            Telephony.Threads.DATE,
            Telephony.Threads.RECIPIENT_IDS,
            Telephony.Threads.SNIPPET,
            Telephony.Threads.READ,
        )
        val summaries = mutableListOf<ThreadSummary>()
        val threadsUri = Telephony.Threads.CONTENT_URI.buildUpon()
            .appendQueryParameter("simple", "true")
            .build()
        providerQuery(
            threadsUri,
            projection,
            sortOrder = "${Telephony.Threads.DATE} DESC",
            timeoutMs = 20_000L,
        ) { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(BaseColumns._ID)
            val dateColumn = cursor.getColumnIndexOrThrow(Telephony.Threads.DATE)
            val recipientsColumn = cursor.getColumnIndexOrThrow(
                Telephony.Threads.RECIPIENT_IDS,
            )
            val snippetColumn = cursor.getColumnIndexOrThrow(
                Telephony.Threads.SNIPPET,
            )
            val readColumn = cursor.getColumnIndexOrThrow(Telephony.Threads.READ)
            while (cursor.moveToNext()) {
                summaries.add(
                    ThreadSummary(
                        id = cursor.getLong(idColumn).toString(),
                        recipientIds = cursor.getString(recipientsColumn)
                            .orEmpty()
                            .trim()
                            .split(Regex("\\s+"))
                            .filter(String::isNotEmpty),
                        preview = cursor.getString(snippetColumn).orEmpty(),
                        updatedAt = normalizedTimestamp(cursor.getLong(dateColumn)),
                        unreadCount = if (cursor.getInt(readColumn) == 0) 1 else 0,
                    ),
                )
            }
        }
        lastLoadStage = "Resolving conversation recipients"
        val addressBook = canonicalAddresses(
            summaries.flatMap { it.recipientIds }.toSet(),
        )
        val resolvedSummaries = summaries.map { summary ->
            val addresses = summary.recipientIds.mapNotNull(addressBook::get)
                .ifEmpty {
                    listOfNotNull(latestSmsAddress(summary.id))
                }
            summary.copy(addresses = addresses)
        }
        lastLoadStage =
            "Encoding ${resolvedSummaries.size} conversation summaries"
        val items = resolvedSummaries.map { summary ->
            val initialTitle = summary.addresses.joinToString(", ")
            hashMapOf<String, Any?>(
                "id" to summary.id,
                "address" to summary.addresses.singleOrNull().orEmpty(),
                "title" to initialTitle.ifEmpty { "Conversation" },
                "preview" to summary.preview,
                "updatedAt" to summary.updatedAt,
                "unreadCount" to summary.unreadCount,
                "avatarBytes" to null,
                "messages" to emptyList<HashMap<String, Any?>>(),
            )
        }
        return ConversationPage(items = items, summaries = resolvedSummaries)
    }

    private fun enrichConversationSummaries(
        summaries: List<ThreadSummary>,
        generation: Int,
    ) {
        Thread {
            val contactCache = mutableMapOf<String, ContactDetails>()
            for (summary in summaries) {
                if (generation != enrichmentGeneration.get()) {
                    break
                }
                val addresses = summary.addresses
                val contacts = addresses.map { address ->
                    contactCache.getOrPut(address) { contactDetails(address) }
                }
                val title = contacts.mapIndexed { index, contact ->
                    contact.name ?: addresses[index]
                }.joinToString(", ").ifEmpty { "Conversation" }
                val update = hashMapOf<String, Any?>(
                    "id" to summary.id,
                    "address" to addresses.singleOrNull().orEmpty(),
                    "title" to title,
                    "avatarBytes" to contacts.singleOrNull()?.avatarBytes,
                )
                mainHandler.post {
                    if (generation == enrichmentGeneration.get() &&
                        ::channel.isInitialized
                    ) {
                        channel.invokeMethod("conversationEnriched", update)
                    }
                }
            }
            Log.i(TAG, "Conversation contact enrichment completed")
        }.start()
    }

    private fun queryThreadMessages(
        threadId: String,
        beforeTimestamp: Long?,
        beforeMessageId: Long?,
        pageSize: Int,
    ): List<HashMap<String, Any?>> {
        val projection = arrayOf(
            BaseColumns._ID,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            Telephony.Sms.TYPE,
        )
        val messages = mutableListOf<HashMap<String, Any?>>()
        val selection = if (beforeTimestamp == null) {
            "${Telephony.Sms.THREAD_ID} = ?"
        } else {
            "${Telephony.Sms.THREAD_ID} = ? AND " +
                "(${Telephony.Sms.DATE} < ? OR " +
                "(${Telephony.Sms.DATE} = ? AND ${BaseColumns._ID} < ?))"
        }
        val selectionArgs = if (beforeTimestamp == null) {
            arrayOf(threadId)
        } else {
            arrayOf(
                threadId,
                beforeTimestamp.toString(),
                beforeTimestamp.toString(),
                (beforeMessageId ?: Long.MAX_VALUE).toString(),
            )
        }
        providerQuery(
            Telephony.Sms.CONTENT_URI,
            projection,
            selection = selection,
            selectionArgs = selectionArgs,
            sortOrder = "${Telephony.Sms.DATE} DESC, " +
                "${BaseColumns._ID} DESC LIMIT $pageSize",
            timeoutMs = 10_000L,
        ) { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(BaseColumns._ID)
            val bodyColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)
            val typeColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.TYPE)
            var processed = 0
            while (cursor.moveToNext() && processed < pageSize) {
                processed += 1
                val type = cursor.getInt(typeColumn)
                val fromMe = type == Telephony.Sms.MESSAGE_TYPE_SENT ||
                    type == Telephony.Sms.MESSAGE_TYPE_OUTBOX ||
                    type == Telephony.Sms.MESSAGE_TYPE_FAILED ||
                    type == Telephony.Sms.MESSAGE_TYPE_QUEUED
                val deliveryState = when (type) {
                    Telephony.Sms.MESSAGE_TYPE_OUTBOX,
                    Telephony.Sms.MESSAGE_TYPE_QUEUED -> "sending"
                    Telephony.Sms.MESSAGE_TYPE_FAILED -> "failed"
                    Telephony.Sms.MESSAGE_TYPE_SENT -> "sent"
                    else -> "delivered"
                }
                messages.add(
                    hashMapOf(
                        "id" to cursor.getLong(idColumn).toString(),
                        "text" to cursor.getString(bodyColumn).orEmpty(),
                        "sentAt" to cursor.getLong(dateColumn),
                        "isFromMe" to fromMe,
                        "deliveryState" to deliveryState,
                    ),
                )
            }
        }
        messages.sortWith(
            compareBy<HashMap<String, Any?>>(
                { (it["sentAt"] as? Long) ?: 0L },
                { (it["id"] as? String)?.toLongOrNull() ?: 0L },
            ),
        )
        return messages
    }

    private fun queryMmsThreadMessages(threadId: String): List<HashMap<String, Any?>> {
        val projection = arrayOf(BaseColumns._ID, "date", "msg_box", "sub")
        val messages = mutableListOf<HashMap<String, Any?>>()
        providerQuery(
            Telephony.Mms.CONTENT_URI,
            projection,
            "thread_id = ?",
            arrayOf(threadId),
            "date DESC LIMIT 20",
            timeoutMs = 2_000L,
        ) { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(BaseColumns._ID)
            val dateColumn = cursor.getColumnIndexOrThrow("date")
            val boxColumn = cursor.getColumnIndexOrThrow("msg_box")
            val subjectColumn = cursor.getColumnIndexOrThrow("sub")
            var processed = 0
            while (cursor.moveToNext() && processed < 20) {
                processed += 1
                val id = cursor.getLong(idColumn).toString()
                val box = cursor.getInt(boxColumn)
                val fromMe = box == Telephony.Mms.MESSAGE_BOX_SENT ||
                    box == Telephony.Mms.MESSAGE_BOX_OUTBOX ||
                    box == Telephony.Mms.MESSAGE_BOX_FAILED
                val deliveryState = when (box) {
                    Telephony.Mms.MESSAGE_BOX_OUTBOX -> "sending"
                    Telephony.Mms.MESSAGE_BOX_FAILED -> "failed"
                    else -> "delivered"
                }
                val subject = cursor.getString(subjectColumn).orEmpty()
                val text = subject.ifBlank { "MMS" }
                messages.add(
                    hashMapOf(
                        "id" to "mms-$id",
                        "text" to text,
                        "sentAt" to cursor.getLong(dateColumn) * 1000L,
                        "isFromMe" to fromMe,
                        "deliveryState" to deliveryState,
                    ),
                )
            }
        }
        return messages
    }

    private fun canonicalAddresses(recipientIds: Set<String>): Map<String, String> {
        if (recipientIds.isEmpty()) return emptyMap()
        val ids = recipientIds.toList()
        return runCatching {
            val addresses = mutableMapOf<String, String>()
            ids.chunked(500).forEach { chunk ->
                val placeholders = List(chunk.size) { "?" }.joinToString(",")
                providerQuery(
                    Uri.parse("content://mms-sms/canonical-addresses"),
                    arrayOf(BaseColumns._ID, "address"),
                    "${BaseColumns._ID} IN ($placeholders)",
                    chunk.toTypedArray(),
                    timeoutMs = 2_000L,
                ) { cursor ->
                    val idColumn = cursor.getColumnIndexOrThrow(BaseColumns._ID)
                    val addressColumn = cursor.getColumnIndexOrThrow("address")
                    while (cursor.moveToNext()) {
                        addresses[cursor.getLong(idColumn).toString()] =
                            cursor.getString(addressColumn).orEmpty()
                    }
                }
            }
            addresses
        }.getOrDefault(emptyMap())
    }

    private fun latestSmsAddress(threadId: String): String? {
        return runCatching {
            providerQuery(
                Telephony.Sms.CONTENT_URI,
                arrayOf(Telephony.Sms.ADDRESS),
                "${Telephony.Sms.THREAD_ID} = ?",
                arrayOf(threadId),
                "${Telephony.Sms.DATE} DESC LIMIT 1",
                timeoutMs = 1_000L,
            ) { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull()
    }

    private fun normalizedTimestamp(value: Long): Long =
        if (value in 1..999_999_999_999L) value * 1000L else value

    private fun contactDetails(address: String): ContactDetails {
        if (address.isEmpty() ||
            checkSelfPermission(Manifest.permission.READ_CONTACTS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return ContactDetails()
        }
        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(address),
        )
        return runCatching {
            providerQuery(
                uri,
                arrayOf(
                    ContactsContract.PhoneLookup.DISPLAY_NAME,
                    ContactsContract.PhoneLookup.PHOTO_THUMBNAIL_URI,
                ),
                timeoutMs = 1_000L,
            ) { cursor ->
                if (!cursor.moveToFirst()) return@providerQuery ContactDetails()
                val photoUri = cursor.getString(1)
                val avatarBytes = photoUri?.let { value ->
                    runCatching {
                        contentResolver.openInputStream(Uri.parse(value))
                            ?.use { it.readBytes() }
                    }.getOrNull()
                }
                ContactDetails(
                    name = cursor.getString(0),
                    avatarBytes = avatarBytes,
                )
            } ?: ContactDetails()
        }.getOrDefault(ContactDetails())
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ROLE_REQUEST) {
            pendingRoleResult?.success(
                resultCode == Activity.RESULT_OK && isDefaultSmsApp(),
            )
            pendingRoleResult = null
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            pendingPermissionResult?.success(hasCoreSmsPermissions())
            pendingPermissionResult = null
        }
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(notifyMessagesChanged)
        if (observerRegistered) contentResolver.unregisterContentObserver(smsObserver)
        super.onDestroy()
    }
}

private data class ConversationPage(
    val items: List<Map<String, Any?>>,
    val summaries: List<ThreadSummary>,
)

private data class ThreadSummary(
    val id: String,
    val recipientIds: List<String>,
    val addresses: List<String> = emptyList(),
    val preview: String,
    val updatedAt: Long,
    val unreadCount: Int,
)

private data class ContactDetails(
    val name: String? = null,
    val avatarBytes: ByteArray? = null,
)
