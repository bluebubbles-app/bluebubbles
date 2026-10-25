package io.github.bluebubblesapp.bluebubbles

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ComponentName
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaMetadataRetriever
import android.media.MediaRecorder
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
import android.provider.OpenableColumns
import android.provider.Settings
import android.provider.MediaStore
import android.provider.Telephony
import android.telephony.SmsManager
import android.util.Log
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "bluebubbles/sms"
        private const val TAG = "BlueBubblesSms"
        private const val NATIVE_BUILD = "2026-10-25-alternate-launcher-icons-v1"
        private const val ROLE_REQUEST = 4701
        private const val PERMISSION_REQUEST = 4702
        private const val MEDIA_PERMISSION_REQUEST = 4703
        private const val CAMERA_REQUEST = 4704
        private const val GALLERY_REQUEST = 4705
        private const val PROVIDER_LOAD_TIMEOUT_MS = 20_000L
        private const val METHOD_REPLY_TIMEOUT_MS = 30_000L
    }

    private lateinit var channel: MethodChannel
    private var pendingRoleResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingMediaPermissionResult: MethodChannel.Result? = null
    private var pendingMediaPermissionKind: String? = null
    private var pendingCameraResult: MethodChannel.Result? = null
    private var pendingCameraUri: Uri? = null
    private var pendingGalleryResult: MethodChannel.Result? = null
    private var voiceRecorder: MediaRecorder? = null
    private var voiceRecordingFile: File? = null
    private var voiceRecordingStartedAt = 0L
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
            "setLauncherIcon" -> setLauncherIcon(call, result)
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
            "sendMms" -> sendMms(call, result)
            "requestMediaPermission" -> requestMediaPermission(call, result)
            "startVoiceRecording" -> startVoiceRecording(result)
            "stopVoiceRecording" -> stopVoiceRecording(result)
            "cancelVoiceRecording" -> cancelVoiceRecording(result)
            "loadRecentImages" -> loadRecentImages(call, result)
            "pickGalleryImage" -> pickGalleryImage(result)
            "takePhoto" -> takePhoto(result)
            "markThreadRead" -> markThreadRead(call, result)
            "deleteMessage" -> deleteMessage(call, result)
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

    private fun setLauncherIcon(call: MethodCall, result: MethodChannel.Result) {
        val requested = call.argument<String>("icon")
        val aliases = mapOf(
            "modernBlue" to ComponentName(this, "$packageName.LauncherModernBlue"),
            "modernGreen" to ComponentName(this, "$packageName.LauncherModernGreen"),
            "classicBlue" to ComponentName(this, "$packageName.LauncherClassicBlue"),
            "classicGreen" to ComponentName(this, "$packageName.LauncherClassicGreen"),
        )
        val selected = aliases[requested]
        if (selected == null) {
            result.error("invalid_launcher_icon", "Unknown launcher icon: $requested", null)
            return
        }

        try {
            packageManager.setComponentEnabledSetting(
                selected,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            aliases.values
                .filterNot { it == selected }
                .forEach { component ->
                    packageManager.setComponentEnabledSetting(
                        component,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                }
            result.success(true)
        } catch (error: Exception) {
            Log.e(TAG, "Unable to change launcher icon", error)
            result.error(
                "launcher_icon_failed",
                error.message ?: "Android could not change the launcher icon.",
                null,
            )
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

    private fun mediaPermissionFor(kind: String): String = when (kind) {
        "audio" -> Manifest.permission.RECORD_AUDIO
        "camera" -> Manifest.permission.CAMERA
        "photos" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        else -> ""
    }

    private fun hasMediaPermission(kind: String): Boolean {
        val permission = mediaPermissionFor(kind)
        if (permission.isEmpty()) return false
        if (hasPermission(permission)) return true
        return kind == "photos" &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            hasPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
    }

    private fun requestMediaPermission(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val kind = call.argument<String>("kind").orEmpty()
        val permission = mediaPermissionFor(kind)
        if (permission.isEmpty()) {
            result.error("invalid_media_permission", "Unknown media permission.", null)
            return
        }
        if (hasMediaPermission(kind)) {
            result.success(true)
            return
        }
        if (pendingMediaPermissionResult != null) {
            result.error("request_active", "A media permission request is active.", null)
            return
        }
        pendingMediaPermissionResult = result
        pendingMediaPermissionKind = kind
        val permissions = if (
            kind == "photos" &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        ) {
            arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
        } else {
            arrayOf(permission)
        }
        requestPermissions(permissions, MEDIA_PERMISSION_REQUEST)
    }

    private fun startVoiceRecording(result: MethodChannel.Result) {
        if (!hasMediaPermission("audio")) {
            result.error("microphone_denied", "Microphone access is not granted.", null)
            return
        }
        if (voiceRecorder != null) {
            result.error("recording_active", "A recording is already active.", null)
            return
        }
        try {
            val directory = File(cacheDir, "voice_messages").apply { mkdirs() }
            val output = File(directory, "voice-${System.currentTimeMillis()}.3gp")
            @Suppress("DEPRECATION")
            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                MediaRecorder()
            }
            recorder.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                // 3GP + AMR-WB is the interoperable carrier-MMS voice format
                // used by QUIK. AAC/MP4 is commonly presented as a generic file.
                setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP)
                setAudioEncoder(MediaRecorder.AudioEncoder.AMR_WB)
                setMaxDuration(5 * 60 * 1000)
                setOutputFile(output.absolutePath)
                prepare()
                start()
            }
            voiceRecorder = recorder
            voiceRecordingFile = output
            voiceRecordingStartedAt = SystemClock.elapsedRealtime()
            result.success(null)
        } catch (error: Exception) {
            releaseVoiceRecorder(deleteFile = true)
            Log.e(TAG, "Voice recording start failed", error)
            result.error("recording_failed", error.message, null)
        }
    }

    private fun stopVoiceRecording(result: MethodChannel.Result) {
        val recorder = voiceRecorder
        val file = voiceRecordingFile
        if (recorder == null || file == null) {
            result.error("no_recording", "No voice recording is active.", null)
            return
        }
        val duration = (SystemClock.elapsedRealtime() - voiceRecordingStartedAt)
            .coerceAtLeast(0L)
        try {
            recorder.stop()
            recorder.release()
            voiceRecorder = null
            voiceRecordingFile = null
            result.success(
                hashMapOf(
                    "uri" to Uri.fromFile(file).toString(),
                    "localPath" to file.absolutePath,
                    "mimeType" to "audio/3gpp",
                    "name" to file.name,
                    "durationMilliseconds" to duration,
                ),
            )
        } catch (error: Exception) {
            releaseVoiceRecorder(deleteFile = true)
            Log.e(TAG, "Voice recording stop failed", error)
            result.error("recording_failed", "The recording was too short.", null)
        }
    }

    private fun cancelVoiceRecording(result: MethodChannel.Result) {
        releaseVoiceRecorder(deleteFile = true)
        result.success(null)
    }

    private fun releaseVoiceRecorder(deleteFile: Boolean) {
        val recorder = voiceRecorder
        voiceRecorder = null
        runCatching { recorder?.stop() }
        runCatching { recorder?.reset() }
        runCatching { recorder?.release() }
        if (deleteFile) runCatching { voiceRecordingFile?.delete() }
        voiceRecordingFile = null
        voiceRecordingStartedAt = 0L
    }

    private fun loadRecentImages(call: MethodCall, result: MethodChannel.Result) {
        if (!hasMediaPermission("photos")) {
            result.error("photos_denied", "Photo access is not granted.", null)
            return
        }
        val limit = (call.argument<Number>("limit")?.toInt() ?: 60)
            .coerceIn(1, 90)
        val offset = (call.argument<Number>("offset")?.toInt() ?: 0)
            .coerceAtLeast(0)
        Thread {
            try {
                val images = mutableListOf<Map<String, Any?>>()
                val projection = arrayOf(
                    MediaStore.Images.Media._ID,
                    MediaStore.Images.Media.DISPLAY_NAME,
                    MediaStore.Images.Media.MIME_TYPE,
                )
                val pagedByProvider = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                val cursor = if (pagedByProvider) {
                    val queryArgs = Bundle().apply {
                        putStringArray(
                            ContentResolver.QUERY_ARG_SORT_COLUMNS,
                            arrayOf(MediaStore.Images.Media.DATE_ADDED),
                        )
                        putInt(
                            ContentResolver.QUERY_ARG_SORT_DIRECTION,
                            ContentResolver.QUERY_SORT_DIRECTION_DESCENDING,
                        )
                        putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
                        putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
                    }
                    contentResolver.query(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        projection,
                        queryArgs,
                        null,
                    )
                } else {
                    contentResolver.query(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        projection,
                        null,
                        null,
                        "${MediaStore.Images.Media.DATE_ADDED} DESC",
                    )
                }
                cursor?.use { mediaCursor ->
                    val idIndex = mediaCursor.getColumnIndexOrThrow(
                        MediaStore.Images.Media._ID,
                    )
                    val nameIndex = mediaCursor.getColumnIndexOrThrow(
                        MediaStore.Images.Media.DISPLAY_NAME,
                    )
                    val mimeIndex = mediaCursor.getColumnIndexOrThrow(
                        MediaStore.Images.Media.MIME_TYPE,
                    )
                    var skipped = 0
                    while (mediaCursor.moveToNext() && images.size < limit) {
                        if (!pagedByProvider && skipped++ < offset) continue
                        val uri = Uri.withAppendedPath(
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            mediaCursor.getLong(idIndex).toString(),
                        )
                        val thumbnail = mediaThumbnail(uri) ?: continue
                        images.add(
                            hashMapOf(
                                "uri" to uri.toString(),
                                "mimeType" to mediaCursor.getString(mimeIndex)
                                    .orEmpty()
                                    .ifEmpty { "image/jpeg" },
                                "name" to mediaCursor.getString(nameIndex),
                                "thumbnailBytes" to thumbnail,
                            ),
                        )
                    }
                }
                runOnUiThread { result.success(images) }
            } catch (error: Exception) {
                Log.e(TAG, "Recent photo load failed", error)
                runOnUiThread {
                    result.error("photos_load_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun mediaThumbnail(uri: Uri): ByteArray? {
        val platformThumbnail = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentResolver.loadThumbnail(uri, Size(320, 320), null)
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Thumbnails.getThumbnail(
                    contentResolver,
                    uri.lastPathSegment?.toLongOrNull() ?: return@runCatching null,
                    MediaStore.Images.Thumbnails.MINI_KIND,
                    null,
                )
            }
        }.getOrNull()
        val bitmap = platformThumbnail ?: runCatching {
            contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        }.getOrNull() ?: return null
        val largestSide = maxOf(bitmap.width, bitmap.height)
        val thumbnail = if (largestSide > 720) {
            val scale = 720f / largestSide.toFloat()
            Bitmap.createScaledBitmap(
                bitmap,
                (bitmap.width * scale).toInt().coerceAtLeast(1),
                (bitmap.height * scale).toInt().coerceAtLeast(1),
                true,
            )
        } else {
            bitmap
        }
        return runCatching {
            ByteArrayOutputStream().use { output ->
                thumbnail.compress(Bitmap.CompressFormat.JPEG, 78, output)
                output.toByteArray()
            }
        }.getOrNull()
    }

    private fun takePhoto(result: MethodChannel.Result) {
        if (!hasMediaPermission("camera")) {
            result.error("camera_denied", "Camera access is not granted.", null)
            return
        }
        if (pendingCameraResult != null) {
            result.error("camera_active", "The camera is already open.", null)
            return
        }
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "BlueBubbles-${System.currentTimeMillis()}.jpg")
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/BlueBubbles")
            }
        }
        val uri = contentResolver.insert(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            values,
        )
        if (uri == null) {
            result.error("camera_failed", "A photo destination could not be created.", null)
            return
        }
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, uri)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        intent.clipData = ClipData.newRawUri("BlueBubbles photo", uri)
        try {
            pendingCameraResult = result
            pendingCameraUri = uri
            startActivityForResult(intent, CAMERA_REQUEST)
        } catch (_: ActivityNotFoundException) {
            pendingCameraResult = null
            pendingCameraUri = null
            contentResolver.delete(uri, null, null)
            result.error("camera_unavailable", "No camera app is available.", null)
        }
    }

    private fun pickGalleryImage(result: MethodChannel.Result) {
        if (pendingGalleryResult != null) {
            result.error("gallery_active", "The photo library is already open.", null)
            return
        }
        val systemPicker = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply { type = "image/*" }
        } else {
            null
        }
        val documentPicker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        val intent = systemPicker?.takeIf {
            it.resolveActivity(packageManager) != null
        } ?: documentPicker
        try {
            pendingGalleryResult = result
            startActivityForResult(intent, GALLERY_REQUEST)
        } catch (_: ActivityNotFoundException) {
            pendingGalleryResult = null
            result.error("gallery_unavailable", "No photo library is available.", null)
        }
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
                suppressProviderReloadUntil =
                    SystemClock.elapsedRealtime() + 750L
                val manager = SmsManager.getDefault()
                SmsSendCompat.send(manager, address, text)
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
                mainHandler.removeCallbacks(notifyMessagesChanged)
                mainHandler.postDelayed(notifyMessagesChanged, 800L)
                runOnUiThread { result.success(inserted.lastPathSegment) }
            } catch (error: Exception) {
                Log.e(TAG, "SMS send failed", error)
                runOnUiThread {
                    result.error("sms_send_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun sendMms(call: MethodCall, result: MethodChannel.Result) {
        if (!isDefaultSmsApp() || !hasCoreSmsPermissions()) {
            result.error("sms_access_denied", "SMS access is not active.", null)
            return
        }
        val address = call.argument<String>("address")?.trim().orEmpty()
        val text = call.argument<String>("text")?.trim().orEmpty()
        val uriValue = call.argument<String>("uri").orEmpty()
        val localPath = call.argument<String>("localPath").orEmpty()
        val mimeType = call.argument<String>("mimeType")
            ?.takeIf { it.isNotBlank() }
            ?: "application/octet-stream"
        val threadId = call.argument<String>("threadId")?.toLongOrNull()
        if (address.isEmpty() || (uriValue.isEmpty() && localPath.isEmpty())) {
            result.error("invalid_mms", "A recipient and attachment are required.", null)
            return
        }
        Thread {
            try {
                val bytes = if (localPath.isNotEmpty()) {
                    File(localPath).readBytes()
                } else {
                    contentResolver.openInputStream(Uri.parse(uriValue))
                        ?.use { it.readBytes() }
                        ?: error("The selected attachment could not be read.")
                }
                val prepared = prepareMmsAttachment(bytes, mimeType)
                runOnUiThread {
                    try {
                        val settings =
                            com.klinker.android.send_message.Settings().apply {
                                setUseSystemSending(true)
                            }
                        val message =
                            com.klinker.android.send_message.Message(text, address).apply {
                                addMedia(
                                    prepared.bytes,
                                    prepared.mimeType,
                                    mmsPartName(prepared.mimeType),
                                )
                            }
                        val transaction =
                            com.klinker.android.send_message.Transaction(this, settings)
                        transaction.setExplicitBroadcastForSentMms(
                            Intent(this, BlueBubblesMmsSentReceiver::class.java),
                        )
                        suppressProviderReloadUntil =
                            SystemClock.elapsedRealtime() + 750L
                        transaction.sendNewMessage(
                            message,
                            threadId
                                ?: com.klinker.android.send_message.Transaction.NO_THREAD_ID,
                        )
                        mainHandler.removeCallbacks(notifyMessagesChanged)
                        mainHandler.postDelayed(notifyMessagesChanged, 800L)
                        result.success(null)
                    } catch (error: Exception) {
                        Log.e(TAG, "MMS enqueue failed", error)
                        result.error("mms_send_failed", error.message, null)
                    }
                }
            } catch (error: Exception) {
                Log.e(TAG, "MMS send failed", error)
                runOnUiThread {
                    result.error("mms_send_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun prepareMmsAttachment(
        bytes: ByteArray,
        mimeType: String,
    ): PreparedMmsAttachment {
        val carrierSafeImage = mimeType.equals("image/jpeg", true) ||
            mimeType.equals("image/png", true)
        if (!mimeType.startsWith("image/") ||
            mimeType.equals("image/gif", true) ||
            (carrierSafeImage && bytes.size <= 600_000)
        ) {
            return PreparedMmsAttachment(bytes, mimeType)
        }
        val bitmap = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ImageDecoder.decodeBitmap(
                    ImageDecoder.createSource(ByteBuffer.wrap(bytes)),
                ) { decoder, info, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    val largestSide = maxOf(info.size.width, info.size.height)
                    if (largestSide > 1_600) {
                        val scale = 1_600f / largestSide.toFloat()
                        decoder.setTargetSize(
                            (info.size.width * scale).toInt().coerceAtLeast(1),
                            (info.size.height * scale).toInt().coerceAtLeast(1),
                        )
                    }
                }
            } else {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }
        }.getOrNull() ?: return PreparedMmsAttachment(bytes, mimeType)

        var quality = 88
        var encoded = bytes
        while (quality >= 48) {
            encoded = ByteArrayOutputStream().use { output ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, output)
                output.toByteArray()
            }
            if (encoded.size <= 600_000) break
            quality -= 8
        }
        return PreparedMmsAttachment(encoded, "image/jpeg")
    }

    private fun mmsPartName(mimeType: String): String = when {
        mimeType.equals("image/jpeg", true) -> "image.jpg"
        mimeType.equals("image/png", true) -> "image.png"
        mimeType.equals("image/gif", true) -> "image.gif"
        mimeType.equals("image/webp", true) -> "image.webp"
        mimeType.equals("audio/mp4", true) -> "audio.m4a"
        mimeType.equals("audio/3gpp", true) -> "voice.3gp"
        mimeType.equals("audio/aac", true) -> "audio.aac"
        mimeType.equals("audio/mpeg", true) -> "audio.mp3"
        mimeType.equals("audio/ogg", true) -> "audio.ogg"
        mimeType.startsWith("image/", true) -> "image.jpg"
        mimeType.startsWith("audio/", true) -> "audio.bin"
        mimeType.startsWith("video/", true) -> "video.mp4"
        else -> "attachment.bin"
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

    private fun deleteMessage(call: MethodCall, result: MethodChannel.Result) {
        if (!isDefaultSmsApp() || !hasCoreSmsPermissions()) {
            result.error("sms_access_denied", "SMS access is not active.", null)
            return
        }
        val threadId = call.argument<String>("threadId").orEmpty()
        val messageId = call.argument<String>("messageId").orEmpty()
        val isMms = messageId.startsWith("mms-")
        val providerId = if (isMms) messageId.removePrefix("mms-") else messageId
        if (threadId.isEmpty() || providerId.toLongOrNull() == null) {
            result.error("invalid_message", "A valid message is required.", null)
            return
        }
        Thread {
            try {
                if (isMms) {
                    contentResolver.delete(
                        Telephony.Mms.CONTENT_URI,
                        "${BaseColumns._ID} = ? AND thread_id = ?",
                        arrayOf(providerId, threadId),
                    )
                } else {
                    contentResolver.delete(
                        Telephony.Sms.CONTENT_URI,
                        "${BaseColumns._ID} = ? AND ${Telephony.Sms.THREAD_ID} = ?",
                        arrayOf(providerId, threadId),
                    )
                }
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
                    "isKnownContact" to contact.isKnown,
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
                // Group threads keep their generated group avatar. The generic
                // silhouette is reserved for unknown one-to-one recipients.
                val isKnownContact = contacts.singleOrNull()?.isKnown ?: true
                val update = hashMapOf<String, Any?>(
                    "id" to summary.id,
                    "address" to addresses.singleOrNull().orEmpty(),
                    "title" to title,
                    "isKnownContact" to isKnownContact,
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
        messages.addAll(
            queryMmsThreadMessages(
                threadId = threadId,
                beforeTimestamp = beforeTimestamp,
                pageSize = pageSize,
            ),
        )
        messages.sortWith(
            compareBy<HashMap<String, Any?>>(
                { (it["sentAt"] as? Long) ?: 0L },
                { (it["id"] as? String)?.toLongOrNull() ?: 0L },
            ),
        )
        return if (messages.size <= pageSize) {
            messages
        } else {
            messages.takeLast(pageSize)
        }
    }

    private fun queryMmsThreadMessages(
        threadId: String,
        beforeTimestamp: Long?,
        pageSize: Int,
    ): List<HashMap<String, Any?>> {
        val projection = arrayOf(BaseColumns._ID, "date", "msg_box", "sub")
        val messages = mutableListOf<HashMap<String, Any?>>()
        val selection = if (beforeTimestamp == null) {
            "thread_id = ?"
        } else {
            "thread_id = ? AND date < ?"
        }
        val selectionArgs = if (beforeTimestamp == null) {
            arrayOf(threadId)
        } else {
            arrayOf(threadId, (beforeTimestamp / 1000L).toString())
        }
        providerQuery(
            Telephony.Mms.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "date DESC LIMIT $pageSize",
            timeoutMs = 5_000L,
        ) { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(BaseColumns._ID)
            val dateColumn = cursor.getColumnIndexOrThrow("date")
            val boxColumn = cursor.getColumnIndexOrThrow("msg_box")
            val subjectColumn = cursor.getColumnIndexOrThrow("sub")
            var processed = 0
            while (cursor.moveToNext() && processed < pageSize) {
                processed += 1
                val id = cursor.getLong(idColumn).toString()
                val box = cursor.getInt(boxColumn)
                val fromMe = box == Telephony.Mms.MESSAGE_BOX_SENT ||
                    box == Telephony.Mms.MESSAGE_BOX_OUTBOX ||
                    box == Telephony.Mms.MESSAGE_BOX_FAILED
                val deliveryState = when (box) {
                    Telephony.Mms.MESSAGE_BOX_OUTBOX -> "sending"
                    Telephony.Mms.MESSAGE_BOX_FAILED -> "failed"
                    Telephony.Mms.MESSAGE_BOX_SENT -> "sent"
                    else -> "delivered"
                }
                val subject = cursor.getString(subjectColumn).orEmpty()
                val content = queryMmsContent(id)
                val text = subject.ifBlank {
                    content.text.ifBlank {
                        if (content.attachment == null) "MMS" else ""
                    }
                }
                messages.add(
                    hashMapOf(
                        "id" to "mms-$id",
                        "text" to text,
                        "sentAt" to cursor.getLong(dateColumn) * 1000L,
                        "isFromMe" to fromMe,
                        "deliveryState" to deliveryState,
                        "attachment" to content.attachment,
                    ),
                )
            }
        }
        return messages
    }

    private fun queryMmsContent(mmsId: String): MmsContent {
        var text = ""
        var attachment: Map<String, Any?>? = null
        providerQuery(
            Uri.parse("content://mms/part"),
            arrayOf(BaseColumns._ID, "ct", "name", "cl", "text"),
            "mid = ?",
            arrayOf(mmsId),
            timeoutMs = 2_000L,
        ) { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(BaseColumns._ID)
            val contentTypeIndex = cursor.getColumnIndexOrThrow("ct")
            val nameIndex = cursor.getColumnIndexOrThrow("name")
            val contentLocationIndex = cursor.getColumnIndexOrThrow("cl")
            val textIndex = cursor.getColumnIndexOrThrow("text")
            while (cursor.moveToNext()) {
                val contentType = cursor.getString(contentTypeIndex).orEmpty()
                if (contentType == "text/plain") {
                    text = cursor.getString(textIndex).orEmpty()
                    continue
                }
                if (attachment != null ||
                    (!contentType.startsWith("image/") &&
                        !contentType.startsWith("audio/"))
                ) {
                    continue
                }
                val partId = cursor.getLong(idIndex).toString()
                val partUri = Uri.parse("content://mms/part/$partId")
                val name = cursor.getString(nameIndex)
                    ?: cursor.getString(contentLocationIndex)
                attachment = if (contentType.startsWith("image/")) {
                    val thumbnail = mediaThumbnail(partUri)
                    val directory = File(cacheDir, "mms_images").apply { mkdirs() }
                    val extension = when (contentType) {
                        "image/png" -> "png"
                        "image/gif" -> "gif"
                        "image/webp" -> "webp"
                        else -> "jpg"
                    }
                    val output = File(directory, "mms-$mmsId-$partId.$extension")
                    if (!output.exists()) {
                        contentResolver.openInputStream(partUri)?.use { input ->
                            output.outputStream().use { target ->
                                input.copyTo(target)
                            }
                        }
                    }
                    hashMapOf(
                        "uri" to partUri.toString(),
                        "mimeType" to contentType,
                        "name" to name,
                        "localPath" to output.takeIf { it.exists() }
                            ?.absolutePath,
                        "thumbnailBytes" to thumbnail,
                    )
                } else {
                    val extension = when (contentType) {
                        "audio/mp4", "audio/aac" -> "m4a"
                        "audio/3gpp" -> "3gp"
                        "audio/mpeg" -> "mp3"
                        "audio/ogg" -> "ogg"
                        else -> "audio"
                    }
                    val directory = File(cacheDir, "mms_audio").apply { mkdirs() }
                    val output = File(directory, "mms-$mmsId-$partId.$extension")
                    if (!output.exists()) {
                        contentResolver.openInputStream(partUri)?.use { input ->
                            output.outputStream().use { target ->
                                input.copyTo(target)
                            }
                        }
                    }
                    val duration = runCatching {
                        val retriever = MediaMetadataRetriever()
                        try {
                            retriever.setDataSource(output.absolutePath)
                            retriever.extractMetadata(
                                MediaMetadataRetriever.METADATA_KEY_DURATION,
                            )?.toLongOrNull()
                        } finally {
                            retriever.release()
                        }
                    }.getOrNull()
                    hashMapOf(
                        "uri" to partUri.toString(),
                        "localPath" to output.absolutePath,
                        "mimeType" to contentType,
                        "name" to name,
                        "durationMilliseconds" to duration,
                    )
                }
            }
        }
        return MmsContent(text = text, attachment = attachment)
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
                    isKnown = true,
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
            return
        }
        if (requestCode == CAMERA_REQUEST) {
            val result = pendingCameraResult
            val uri = pendingCameraUri
            pendingCameraResult = null
            pendingCameraUri = null
            if (resultCode != Activity.RESULT_OK || uri == null) {
                if (uri != null) contentResolver.delete(uri, null, null)
                result?.success(null)
                return
            }
            Thread {
                val thumbnail = mediaThumbnail(uri)
                runOnUiThread {
                    result?.success(
                        hashMapOf(
                            "uri" to uri.toString(),
                            "mimeType" to "image/jpeg",
                            "name" to "BlueBubbles photo.jpg",
                            "thumbnailBytes" to thumbnail,
                        ),
                    )
                }
            }.start()
            return
        }
        if (requestCode == GALLERY_REQUEST) {
            val result = pendingGalleryResult
            pendingGalleryResult = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                result?.success(null)
                return
            }
            val persistableFlags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            if (persistableFlags != 0) {
                runCatching {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        persistableFlags,
                    )
                }
            }
            Thread {
                val thumbnail = mediaThumbnail(uri)
                val mimeType = contentResolver.getType(uri)
                    .orEmpty()
                    .ifEmpty { "image/jpeg" }
                val name = runCatching {
                    contentResolver.query(
                        uri,
                        arrayOf(OpenableColumns.DISPLAY_NAME),
                        null,
                        null,
                        null,
                    )?.use { cursor ->
                        if (cursor.moveToFirst()) cursor.getString(0) else null
                    }
                }.getOrNull() ?: "Photo"
                runOnUiThread {
                    result?.success(
                        hashMapOf(
                            "uri" to uri.toString(),
                            "mimeType" to mimeType,
                            "name" to name,
                            "thumbnailBytes" to thumbnail,
                        ),
                    )
                }
            }.start()
            return
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
            return
        }
        if (requestCode == MEDIA_PERMISSION_REQUEST) {
            val kind = pendingMediaPermissionKind.orEmpty()
            pendingMediaPermissionResult?.success(hasMediaPermission(kind))
            pendingMediaPermissionResult = null
            pendingMediaPermissionKind = null
        }
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(notifyMessagesChanged)
        releaseVoiceRecorder(deleteFile = true)
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
    val isKnown: Boolean = false,
)

private data class MmsContent(
    val text: String,
    val attachment: Map<String, Any?>?,
)

private data class PreparedMmsAttachment(
    val bytes: ByteArray,
    val mimeType: String,
)
