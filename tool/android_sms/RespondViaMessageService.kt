package io.github.bluebubblesapp.bluebubbles

import android.app.Service
import android.content.ContentValues
import android.content.Intent
import android.os.IBinder
import android.provider.Telephony
import android.telephony.SmsManager

class RespondViaMessageService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val address = intent?.data?.schemeSpecificPart.orEmpty()
        val text = intent?.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        if (address.isNotEmpty() && text.isNotEmpty()) {
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
            } catch (_: Exception) {
                // The caller has no result channel; a normal in-app send reports errors.
            }
        }
        stopSelf(startId)
        return START_NOT_STICKY
    }
}
