package io.github.bluebubblesapp.bluebubbles

import android.Manifest
import android.app.Activity
import android.app.role.RoleManager
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.BaseColumns
import android.provider.ContactsContract
import android.provider.Settings
import android.provider.Telephony
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "bluebubbles/sms"
        private const val ROLE_REQUEST = 4701
        private const val PERMISSION_REQUEST = 4702
    }

    private lateinit var channel: MethodChannel
    private var pendingRoleResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var observerRegistered = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val notifyMessagesChanged = Runnable {
        if (::channel.isInitialized) channel.invokeMethod("messagesChanged", null)
    }
    private val smsObserver = object : ContentObserver(mainHandler) {
        override fun onChange(selfChange: Boolean) {
            mainHandler.removeCallbacks(notifyMessagesChanged)
            mainHandler.postDelayed(notifyMessagesChanged, 250)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        observerRegistered = true
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> result.success(currentState())
            "requestDefaultSmsRole" -> requestDefaultSmsRole(result)
            "requestSmsPermissions" -> requestSmsPermissions(result)
            "loadConversations" -> loadConversations(result)
            "loadThreadMessages" -> loadThreadMessages(call, result)
            "sendSms" -> sendSms(call, result)
            "markThreadRead" -> markThreadRead(call, result)
            "deleteThread" -> deleteThread(call, result)
            "dialNumber" -> dialNumber(call, result)
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
        Thread {
            try {
                val conversations = querySmsConversations()
                runOnUiThread { result.success(conversations) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("sms_query_failed", error.message, null)
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
                contentResolver.insert(Telephony.Sms.Sent.CONTENT_URI, values)
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
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
        Thread {
            try {
                val messages = queryThreadMessages(threadId)
                runOnUiThread { result.success(messages) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("sms_query_failed", error.message, null)
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
        try {
            contentResolver.update(
                Telephony.Sms.CONTENT_URI,
                values,
                "${Telephony.Sms.THREAD_ID} = ?",
                arrayOf(threadId),
            )
            result.success(null)
        } catch (error: Exception) {
            result.error("sms_update_failed", error.message, null)
        }
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
        try {
            contentResolver.delete(
                Telephony.Sms.CONTENT_URI,
                "${Telephony.Sms.THREAD_ID} = ?",
                arrayOf(threadId),
            )
            result.success(null)
        } catch (error: Exception) {
            result.error("sms_delete_failed", error.message, null)
        }
    }

    private fun querySmsConversations(): List<Map<String, Any?>> {
        val projection = arrayOf(
            Telephony.Sms.THREAD_ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            Telephony.Sms.TYPE,
            Telephony.Sms.READ,
        )
        val conversations = linkedMapOf<String, SmsConversationBuilder>()
        val contactCache = mutableMapOf<String, ContactDetails>()
        contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            projection,
            null,
            null,
            "${Telephony.Sms.DATE} DESC",
        )?.use { cursor ->
            val threadColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.THREAD_ID)
            val addressColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)
            val typeColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.TYPE)
            val readColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.READ)
            var processed = 0
            while (cursor.moveToNext() && processed < 5000) {
                processed += 1
                val threadId = cursor.getLong(threadColumn).toString()
                val address = cursor.getString(addressColumn).orEmpty()
                val body = cursor.getString(bodyColumn).orEmpty()
                val date = cursor.getLong(dateColumn)
                val type = cursor.getInt(typeColumn)
                val fromMe = type == Telephony.Sms.MESSAGE_TYPE_SENT ||
                    type == Telephony.Sms.MESSAGE_TYPE_OUTBOX ||
                    type == Telephony.Sms.MESSAGE_TYPE_FAILED ||
                    type == Telephony.Sms.MESSAGE_TYPE_QUEUED
                val builder = conversations.getOrPut(threadId) {
                    val contact = contactCache.getOrPut(address) {
                        contactDetails(address)
                    }
                    SmsConversationBuilder(
                        id = threadId,
                        address = address,
                        title = contact.name ?: address,
                        preview = body,
                        updatedAt = date,
                        avatarBytes = contact.avatarBytes,
                    )
                }
                if (!fromMe && cursor.getInt(readColumn) == 0) {
                    builder.unreadCount += 1
                }
            }
        }
        return conversations.values.map { builder ->
            hashMapOf<String, Any?>(
                "id" to builder.id,
                "address" to builder.address,
                "title" to builder.title,
                "preview" to builder.preview,
                "updatedAt" to builder.updatedAt,
                "unreadCount" to builder.unreadCount,
                "avatarBytes" to builder.avatarBytes,
                "messages" to emptyList<HashMap<String, Any?>>(),
            )
        }
    }

    private fun queryThreadMessages(threadId: String): List<HashMap<String, Any?>> {
        val projection = arrayOf(
            BaseColumns._ID,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            Telephony.Sms.TYPE,
        )
        val messages = mutableListOf<HashMap<String, Any?>>()
        contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            projection,
            "${Telephony.Sms.THREAD_ID} = ?",
            arrayOf(threadId),
            "${Telephony.Sms.DATE} DESC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(BaseColumns._ID)
            val bodyColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)
            val typeColumn = cursor.getColumnIndexOrThrow(Telephony.Sms.TYPE)
            var processed = 0
            while (cursor.moveToNext() && processed < 500) {
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
        messages.reverse()
        return messages
    }

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
        contentResolver.query(
            uri,
            arrayOf(
                ContactsContract.PhoneLookup.DISPLAY_NAME,
                ContactsContract.PhoneLookup.PHOTO_THUMBNAIL_URI,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val photoUri = cursor.getString(1)
                val avatarBytes = photoUri?.let { value ->
                    runCatching {
                        contentResolver.openInputStream(Uri.parse(value))
                            ?.use { it.readBytes() }
                    }.getOrNull()
                }
                return ContactDetails(
                    name = cursor.getString(0),
                    avatarBytes = avatarBytes,
                )
            }
        }
        return ContactDetails()
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

private data class SmsConversationBuilder(
    val id: String,
    val address: String,
    val title: String,
    val preview: String,
    val updatedAt: Long,
    val avatarBytes: ByteArray? = null,
    var unreadCount: Int = 0,
)

private data class ContactDetails(
    val name: String? = null,
    val avatarBytes: ByteArray? = null,
)
