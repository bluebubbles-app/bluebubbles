package io.github.bluebubblesapp.bluebubbles

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.provider.Telephony
import android.telephony.SmsManager
import android.util.Log

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (parts.isEmpty()) return

        val pendingResult = goAsync()
        val appContext = context.applicationContext
        Thread {
            try {
                val address = parts.first().displayOriginatingAddress.orEmpty()
                val body = parts.joinToString(separator = "") {
                    it.displayMessageBody.orEmpty()
                }
                val sentAt = parts.first().timestampMillis.takeIf { it > 0 }
                    ?: System.currentTimeMillis()
                val threadId = MessageNotifier.threadIdFor(appContext, address)
                val values = ContentValues().apply {
                    put(Telephony.Sms.ADDRESS, address)
                    put(Telephony.Sms.BODY, body)
                    put(Telephony.Sms.DATE, System.currentTimeMillis())
                    put(Telephony.Sms.DATE_SENT, sentAt)
                    put(Telephony.Sms.READ, 0)
                    put(Telephony.Sms.SEEN, 0)
                    threadId?.let { put(Telephony.Sms.THREAD_ID, it) }
                }
                appContext.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, values)
                MessageNotifier.show(appContext, address, body, sentAt, threadId)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }
}

class NotificationActionReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BlueBubblesReply"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        val appContext = context.applicationContext
        Thread {
            try {
                when (intent.action) {
                    MessageNotifier.ACTION_REPLY -> reply(appContext, intent)
                    MessageNotifier.ACTION_MARK_READ -> markRead(appContext, intent)
                }
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun reply(context: Context, intent: Intent) {
        val address = intent.getStringExtra(MessageNotifier.EXTRA_ADDRESS).orEmpty()
        val replyText = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(MessageNotifier.KEY_TEXT_REPLY)
            ?.toString()
            ?.trim()
            .orEmpty()
        if (address.isEmpty() || replyText.isEmpty()) return

        runCatching {
            val manager = SmsManager.getDefault()
            val parts = manager.divideMessage(replyText)
            if (parts.size > 1) {
                manager.sendMultipartTextMessage(address, null, parts, null, null)
            } else {
                manager.sendTextMessage(address, null, replyText, null, null)
            }
            val now = System.currentTimeMillis()
            val values = ContentValues().apply {
                put(Telephony.Sms.ADDRESS, address)
                put(Telephony.Sms.BODY, replyText)
                put(Telephony.Sms.DATE, now)
                put(Telephony.Sms.DATE_SENT, now)
                put(Telephony.Sms.READ, 1)
                put(Telephony.Sms.SEEN, 1)
                intent.threadId()?.let { put(Telephony.Sms.THREAD_ID, it) }
            }
            val inserted = context.contentResolver.insert(
                Telephony.Sms.Sent.CONTENT_URI,
                values,
            ) ?: error("The sent SMS provider rejected the quick reply.")
            intent.threadId()?.let { MessageNotifier.markThreadRead(context, it) }
            MessageNotifier.cancel(context, intent.notificationId())
            Log.i(TAG, "Quick reply stored at $inserted")
        }.onFailure { error ->
            Log.e(TAG, "Quick reply failed", error)
        }
    }

    private fun markRead(context: Context, intent: Intent) {
        val threadId = intent.threadId() ?: return
        runCatching {
            MessageNotifier.markThreadRead(context, threadId)
            MessageNotifier.cancel(context, intent.notificationId())
        }
    }

    private fun Intent.threadId(): Long? =
        getStringExtra(MessageNotifier.EXTRA_THREAD_ID)?.toLongOrNull()

    private fun Intent.notificationId(): Int =
        getIntExtra(MessageNotifier.EXTRA_NOTIFICATION_ID, 0)
}

internal object MessageNotifier {
    internal const val ACTION_REPLY =
        "io.github.bluebubblesapp.bluebubbles.action.REPLY"
    internal const val ACTION_MARK_READ =
        "io.github.bluebubblesapp.bluebubbles.action.MARK_READ"
    internal const val KEY_TEXT_REPLY = "bluebubbles_notification_reply"
    internal const val EXTRA_ADDRESS = "address"
    internal const val EXTRA_THREAD_ID = "thread_id"
    internal const val EXTRA_NOTIFICATION_ID = "notification_id"

    private const val CHANNEL_ID = "bluebubbles_messages"

    fun show(
        context: Context,
        address: String,
        body: String,
        timestamp: Long = System.currentTimeMillis(),
        threadId: Long? = null,
        enableActions: Boolean = true,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val manager = context.getSystemService(NotificationManager::class.java)
        ensureChannel(manager)
        val contact = resolveContact(context, address)
        val displayName = contact.name?.takeIf { it.isNotBlank() }
            ?: address.takeIf { it.isNotBlank() }
            ?: "New message"
        val resolvedThreadId = threadId ?: if (enableActions) {
            threadIdFor(context, address)
        } else {
            null
        }
        val notificationId = notificationId(resolvedThreadId, address)

        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        resolvedThreadId?.let { launchIntent.putExtra(EXTRA_THREAD_ID, it.toString()) }
        val contentIntent = PendingIntent.getActivity(
            context,
            notificationId,
            launchIntent,
            immutableFlags(),
        )
        val shortcutId = if (resolvedThreadId != null) {
            publishConversationShortcut(
                context = context,
                threadId = resolvedThreadId,
                displayName = displayName,
                address = address,
                avatar = contact.avatar,
                launchIntent = launchIntent,
            )
        } else {
            null
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(displayName)
            .setContentText(body)
            .setContentIntent(contentIntent)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setWhen(timestamp)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && shortcutId != null) {
            builder.setShortcutId(shortcutId)
        }
        contact.avatar?.let(builder::setLargeIcon)
        applyMessageStyle(builder, displayName, body, timestamp, contact.avatar)

        if (enableActions && resolvedThreadId != null) {
            builder.addAction(
                Notification.Action.Builder(
                    0,
                    "Reply",
                    replyPendingIntent(
                        context,
                        notificationId,
                        resolvedThreadId,
                        address,
                    ),
                )
                    .addRemoteInput(
                        RemoteInput.Builder(KEY_TEXT_REPLY)
                            .setLabel("Reply")
                            .build(),
                    )
                    .build(),
            )
            builder.addAction(
                Notification.Action.Builder(
                    0,
                    "Mark as read",
                    markReadPendingIntent(context, notificationId, resolvedThreadId),
                ).build(),
            )
        }

        manager.notify(notificationId, builder.build())
    }

    fun threadIdFor(context: Context, address: String): Long? {
        if (address.isBlank()) return null
        return runCatching {
            Telephony.Threads.getOrCreateThreadId(context, setOf(address))
        }.getOrNull()
    }

    fun markThreadRead(context: Context, threadId: Long) {
        val values = ContentValues().apply {
            put(Telephony.Sms.READ, 1)
            put(Telephony.Sms.SEEN, 1)
        }
        val selection = "${Telephony.Sms.THREAD_ID} = ? AND " +
            "(${Telephony.Sms.READ} = 0 OR ${Telephony.Sms.SEEN} = 0)"
        val args = arrayOf(threadId.toString())
        context.contentResolver.update(
            Telephony.Sms.CONTENT_URI,
            values,
            selection,
            args,
        )
        context.contentResolver.update(
            Telephony.Mms.CONTENT_URI,
            values,
            selection,
            args,
        )
    }

    fun cancel(context: Context, notificationId: Int) {
        if (notificationId == 0) return
        context.getSystemService(NotificationManager::class.java)
            .cancel(notificationId)
    }

    private fun applyMessageStyle(
        builder: Notification.Builder,
        displayName: String,
        body: String,
        timestamp: Long,
        avatar: Bitmap?,
    ) {
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P -> {
                val senderBuilder = Person.Builder().setName(displayName)
                avatar?.let { senderBuilder.setIcon(Icon.createWithBitmap(it)) }
                val sender = senderBuilder.build()
                val user = Person.Builder().setName("You").build()
                builder.setStyle(
                    Notification.MessagingStyle(user)
                        .addMessage(body, timestamp, sender),
                )
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N -> {
                @Suppress("DEPRECATION")
                builder.setStyle(
                    Notification.MessagingStyle("You")
                        .addMessage(body, timestamp, displayName),
                )
            }
            else -> builder.setStyle(Notification.BigTextStyle().bigText(body))
        }
    }

    private fun resolveContact(context: Context, address: String): NotificationContact {
        if (address.isBlank() ||
            context.checkSelfPermission(Manifest.permission.READ_CONTACTS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return NotificationContact()
        }
        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(address),
        )
        return runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(
                    ContactsContract.PhoneLookup.DISPLAY_NAME,
                    ContactsContract.PhoneLookup.PHOTO_THUMBNAIL_URI,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return@use NotificationContact()
                val photoUri = cursor.getString(1)
                val avatar = photoUri?.let { value ->
                    runCatching {
                        context.contentResolver.openInputStream(Uri.parse(value))
                            ?.use(BitmapFactory::decodeStream)
                    }.getOrNull()
                }
                NotificationContact(cursor.getString(0), avatar)
            } ?: NotificationContact()
        }.getOrDefault(NotificationContact())
    }

    private fun replyPendingIntent(
        context: Context,
        notificationId: Int,
        threadId: Long,
        address: String,
    ): PendingIntent {
        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = ACTION_REPLY
            data = Uri.parse("bluebubbles://notification/reply/$threadId")
            putExtra(EXTRA_ADDRESS, address)
            putExtra(EXTRA_THREAD_ID, threadId.toString())
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
        return PendingIntent.getBroadcast(context, notificationId, intent, flags)
    }

    private fun markReadPendingIntent(
        context: Context,
        notificationId: Int,
        threadId: Long,
    ): PendingIntent {
        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = ACTION_MARK_READ
            data = Uri.parse("bluebubbles://notification/read/$threadId")
            putExtra(EXTRA_THREAD_ID, threadId.toString())
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }
        return PendingIntent.getBroadcast(
            context,
            notificationId xor 0x40000000,
            intent,
            immutableFlags(),
        )
    }

    private fun immutableFlags(): Int = PendingIntent.FLAG_UPDATE_CURRENT or
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }

    private fun publishConversationShortcut(
        context: Context,
        threadId: Long,
        displayName: String,
        address: String,
        avatar: Bitmap?,
        launchIntent: Intent,
    ): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val shortcutId = "sms-conversation-$threadId"
        return runCatching {
            val personBuilder = Person.Builder()
                .setName(displayName)
                .setKey(address.ifBlank { threadId.toString() })
            if (address.isNotBlank()) personBuilder.setUri("tel:$address")
            avatar?.let { personBuilder.setIcon(Icon.createWithBitmap(it)) }

            val shortcutBuilder = ShortcutInfo.Builder(context, shortcutId)
                .setShortLabel(displayName.take(25))
                .setLongLabel(displayName)
                .setIntent(Intent(launchIntent).apply { action = Intent.ACTION_VIEW })
                .setLongLived(true)
                .setPerson(personBuilder.build())
            avatar?.let { shortcutBuilder.setIcon(Icon.createWithBitmap(it)) }
            val shortcut = shortcutBuilder.build()
            val manager = context.getSystemService(ShortcutManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                manager.pushDynamicShortcut(shortcut)
            } else {
                manager.addDynamicShortcuts(listOf(shortcut))
            }
            shortcutId
        }.getOrNull()
    }

    private fun notificationId(threadId: Long?, address: String): Int {
        val raw = threadId?.hashCode() ?: address.hashCode()
        return (raw and Int.MAX_VALUE).takeIf { it != 0 } ?: 1
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Messages",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Incoming SMS and MMS messages"
                },
            )
        }
    }
}

private data class NotificationContact(
    val name: String? = null,
    val avatar: Bitmap? = null,
)
