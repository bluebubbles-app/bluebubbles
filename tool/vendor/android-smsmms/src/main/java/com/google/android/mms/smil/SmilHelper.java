package com.google.android.mms.smil;

import android.util.Log;

import com.android.mms.dom.smil.SmilDocumentImpl;
import com.google.android.mms.ContentType;
import com.google.android.mms.pdu_alt.PduBody;
import com.google.android.mms.pdu_alt.PduPart;
import org.w3c.dom.smil.*;


public class SmilHelper {

    public static final String ELEMENT_TAG_TEXT = "text";
    public static final String ELEMENT_TAG_IMAGE = "img";
    public static final String ELEMENT_TAG_AUDIO = "audio";
    public static final String ELEMENT_TAG_VIDEO = "video";
    public static final String ELEMENT_TAG_VCARD = "vcard";

    public static SMILDocument createSmilDocument(PduBody pb) {

        SMILDocument document = new SmilDocumentImpl();

        // Create root element.
        SMILElement smil = (SMILElement) document.createElement("smil");
        smil.setAttribute("xmlns", "http://www.w3.org/2001/SMIL20/Language");
        document.appendChild(smil);

        // Create <head> and <layout> element.
        SMILElement head = (SMILElement) document.createElement("head");
        smil.appendChild(head);

        SMILLayoutElement layout = (SMILLayoutElement) document.createElement("layout");
        head.appendChild(layout);

        boolean hasTextPart = false;
        boolean hasVisualPart = false;
        for (int i = 0; i < pb.getPartsNum(); i++) {
            String type = new String(pb.getPart(i).getContentType());
            hasTextPart |= type.equals(ContentType.TEXT_PLAIN)
                    || type.equalsIgnoreCase(ContentType.APP_WAP_XHTML)
                    || type.equals(ContentType.TEXT_HTML);
            hasVisualPart |= ContentType.isImageType(type) || ContentType.isVideoType(type);
        }

        SMILElement rootLayout = (SMILElement) document.createElement("root-layout");
        layout.appendChild(rootLayout);

        if (hasVisualPart) {
            SMILElement imageRegion = (SMILElement) document.createElement("region");
            imageRegion.setAttribute("id", "Image");
            imageRegion.setAttribute("fit", "meet");
            imageRegion.setAttribute("left", "0");
            imageRegion.setAttribute("top", "0");
            imageRegion.setAttribute("width", "100%");
            imageRegion.setAttribute("height", hasTextPart ? "80%" : "100%");
            layout.appendChild(imageRegion);
        }

        if (hasTextPart) {
            SMILElement textRegion = (SMILElement) document.createElement("region");
            textRegion.setAttribute("id", "Text");
            textRegion.setAttribute("left", "0");
            textRegion.setAttribute("top", hasVisualPart ? "80%" : "0");
            textRegion.setAttribute("width", "100%");
            textRegion.setAttribute("height", hasVisualPart ? "20%" : "100%");
            layout.appendChild(textRegion);
        }

        // Create <body> element and add a empty <par>.
        SMILElement body = (SMILElement) document.createElement("body");
        smil.appendChild(body);
        SMILParElement par = addPar(document);

        // Create media objects for the parts in PDU.
        int partsNum = pb.getPartsNum();
        if (partsNum == 0) {
            return document;
        }

        boolean hasText = false;
        boolean hasMedia = false;
        for (int i = 0; i < partsNum; i++) {
            // Create new <par> element.
            if ((par == null) || (hasMedia && hasText)) {
                par = addPar(document);
                hasText = false;
                hasMedia = false;
            }

            PduPart part = pb.getPart(i);
            String contentType = new String(part.getContentType());

            if (contentType.equals(ContentType.TEXT_PLAIN)
                    || contentType.equalsIgnoreCase(ContentType.APP_WAP_XHTML)
                    || contentType.equals(ContentType.TEXT_HTML)) {
                SMILMediaElement textElement = createMediaElement(
                        ELEMENT_TAG_TEXT, document, part.generateLocation());
                par.appendChild(textElement);
                hasText = true;
            } else if (ContentType.isImageType(contentType)) {
                SMILMediaElement imageElement = createMediaElement(
                        ELEMENT_TAG_IMAGE, document, part.generateLocation());
                par.appendChild(imageElement);
                hasMedia = true;
            } else if (ContentType.isVideoType(contentType)) {
                SMILMediaElement videoElement = createMediaElement(
                        ELEMENT_TAG_VIDEO, document, part.generateLocation());
                par.appendChild(videoElement);
                hasMedia = true;
            } else if (ContentType.isAudioType(contentType)) {
                SMILMediaElement audioElement = createMediaElement(
                        ELEMENT_TAG_AUDIO, document, part.generateLocation());
                par.appendChild(audioElement);
                hasMedia = true;
            } else if (contentType.equals(ContentType.TEXT_VCARD)) {
                SMILMediaElement textElement = createMediaElement(
                        ELEMENT_TAG_VCARD, document, part.generateLocation());
                par.appendChild(textElement);
                hasMedia = true;
            } else {
                Log.e("creating_smil_document", "unknown mimetype");
            }
        }

        return document;
    }

    public static SMILParElement addPar(SMILDocument document) {
        SMILParElement par = (SMILParElement) document.createElement("par");
        // Set duration to eight seconds by default.
        par.setDur(8.0f);
        document.getBody().appendChild(par);
        return par;
    }

    public static SMILMediaElement createMediaElement(
            String tag, SMILDocument document, String src) {
        SMILMediaElement mediaElement =
                (SMILMediaElement) document.createElement(tag);
        mediaElement.setSrc(escapeXML(src));
        if (tag.equals(ELEMENT_TAG_IMAGE) || tag.equals(ELEMENT_TAG_VIDEO)) {
            mediaElement.setAttribute("region", "Image");
        } else if (tag.equals(ELEMENT_TAG_TEXT)) {
            mediaElement.setAttribute("region", "Text");
        }
        return mediaElement;
    }

    public static String escapeXML(String str) {
        return str.replaceAll("&","&amp;")
                .replaceAll("<", "&lt;")
                .replaceAll(">", "&gt;")
                .replaceAll("\"", "&quot;")
                .replaceAll("'", "&apos;");
    }
}
