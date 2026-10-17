package io.github.bluebubblesapp.bluebubbles

import android.telephony.SmsManager
import android.util.Log
import java.util.ArrayList

/** Sends SMS without failing when a device blocks the SIM GID lookup used by divideMessage. */
internal object SmsSendCompat {
    private const val TAG = "BlueBubblesSms"
    private const val GSM_SINGLE_LIMIT = 160
    private const val GSM_MULTIPART_LIMIT = 153
    private const val UNICODE_SINGLE_LIMIT = 70
    private const val UNICODE_MULTIPART_LIMIT = 67

    private val gsmBasicCharacters = setOf(
        '@', '£', '$', '¥', 'è', 'é', 'ù', 'ì', 'ò', 'Ç', '\n', 'Ø', 'ø',
        '\r', 'Å', 'å', 'Δ', '_', 'Φ', 'Γ', 'Λ', 'Ω', 'Π', 'Ψ', 'Σ', 'Θ',
        'Ξ', 'Æ', 'æ', 'ß', 'É', ' ', '!', '"', '#', '¤', '%', '&', '\'',
        '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5',
        '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '¡', 'A', 'B', 'C',
        'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q',
        'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'Ä', 'Ö', 'Ñ', 'Ü', '§',
        '¿', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
        'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'ä',
        'ö', 'ñ', 'ü', 'à',
    )
    private val gsmExtendedCharacters = setOf('\u000C', '^', '{', '}', '\\', '[', '~', ']', '|', '€')

    fun send(manager: SmsManager, address: String, text: String) {
        val parts = try {
            manager.divideMessage(text)
        } catch (error: SecurityException) {
            Log.w(TAG, "Android SMS fragmentation was denied; using local fragmentation", error)
            divideLocally(text)
        }
        if (parts.size > 1) {
            manager.sendMultipartTextMessage(address, null, parts, null, null)
        } else {
            manager.sendTextMessage(address, null, text, null, null)
        }
    }

    private fun divideLocally(text: String): ArrayList<String> {
        val gsmLength = gsmLength(text)
        if (gsmLength != null) {
            if (gsmLength <= GSM_SINGLE_LIMIT) return arrayListOf(text)
            return splitGsm(text, GSM_MULTIPART_LIMIT)
        }
        if (text.length <= UNICODE_SINGLE_LIMIT) return arrayListOf(text)
        return splitUnicode(text, UNICODE_MULTIPART_LIMIT)
    }

    private fun gsmLength(text: String): Int? {
        var length = 0
        text.forEach { character ->
            length += when (character) {
                in gsmBasicCharacters -> 1
                in gsmExtendedCharacters -> 2
                else -> return null
            }
        }
        return length
    }

    private fun splitGsm(text: String, limit: Int): ArrayList<String> {
        val parts = arrayListOf<String>()
        var start = 0
        var length = 0
        text.forEachIndexed { index, character ->
            val characterLength = if (character in gsmExtendedCharacters) 2 else 1
            if (length + characterLength > limit) {
                parts.add(text.substring(start, index))
                start = index
                length = 0
            }
            length += characterLength
        }
        if (start < text.length) parts.add(text.substring(start))
        return parts
    }

    private fun splitUnicode(text: String, limit: Int): ArrayList<String> {
        val parts = arrayListOf<String>()
        var start = 0
        while (start < text.length) {
            var end = minOf(start + limit, text.length)
            if (end < text.length &&
                Character.isHighSurrogate(text[end - 1]) &&
                Character.isLowSurrogate(text[end])
            ) {
                end--
            }
            parts.add(text.substring(start, end))
            start = end
        }
        return parts
    }
}
