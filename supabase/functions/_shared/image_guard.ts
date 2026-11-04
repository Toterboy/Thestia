/**
 * Bild-Waechter: "wenn nur Bilder hochgeladen werden duerfen, dann nur
 * Bilder".
 *
 * WARUM DAS EIGENTLICH SELBSTVERSTAENDLICH IST - UND TROTZDEM FEHLTE:
 *
 * Der Client waehlt Bilder ueber den System-Picker, der nur Bilder
 * zeigt. Das ist aber eine EMPFEHLUNG, keine Grenze: der Client laesst
 * sich patchen, und auf manchen Geraeten kommt aus der Dateiverwaltung
 * etwas anderes zurueck als ein Bild.
 *
 * Deshalb wird der Dateityp am SERVER an den Magic Bytes geprueft.
 * Das ist die einzige Pruefung, die sich nicht selbst taeuschen
 * laesst: eine Dateiendung oder ein MIME-Typ im Request ist eine
 * Behauptung des Clients, die Magic Bytes sind es nicht.
 *
 * WICHTIG: Das gilt nur dort, wo der Server das Bild in KLARTEXT
 * sieht. Chat-Bilder und Avatare werden clientseitig verschluesselt
 * (AES-256-GCM) - der Server kann sie nicht pruefen, und soll es auch
 * nicht. Fuer diese Pfade ist die clientseitige Pruefung die Grenze.
 */

/**
 * Dekodiert Base64, ohne die Funktion zu verlassen.
 *
 * atob wirft bei ungueltigem Input - und der Input kommt vom Client.
 * Ein data-URL-Praefix wird toleriert.
 */
export function decodeBase64(data: string): Uint8Array | null {
  try {
    const ohnePraefix = data.startsWith("data:")
      ? data.slice(data.indexOf(",") + 1)
      : data;
    const bin = atob(ohnePraefix);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  } catch (_) {
    return null;
  }
}

/**
 * Erkennt den Bildtyp an den Magic Bytes.
 *
 *   JPEG: FF D8 FF
 *   PNG:  89 50 4E 47 0D 0A 1A 0A
 *   WebP: "RIFF" .... "WEBP"
 */
export function erkennBildtyp(
  bytes: Uint8Array,
): "image/jpeg" | "image/png" | "image/webp" | null {
  if (
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  ) {
    return "image/jpeg";
  }
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  ) {
    return "image/png";
  }
  if (
    bytes.length >= 12 &&
    bytes[0] === 0x52 &&
    bytes[1] === 0x49 &&
    bytes[2] === 0x46 &&
    bytes[3] === 0x46 &&
    bytes[8] === 0x57 &&
    bytes[9] === 0x45 &&
    bytes[10] === 0x42 &&
    bytes[11] === 0x50
  ) {
    return "image/webp";
  }
  return null;
}

/** Die Dateiendung, die zum erkannten Typ gehoert. */
export function endungFuer(t: "image/jpeg" | "image/png" | "image/webp"): string {
  if (t === "image/png") return ".png";
  if (t === "image/webp") return ".webp";
  return ".jpg";
}

/**
 * Prueft eine Base64-Datei auf einen Bildtyp.
 *
 * Gibt den erkannten Typ zurueck oder null, wenn es kein Bild ist
 * (oder kein gueltiges Base64).
 */
export function pruefeAufBild(
  base64: string,
): "image/jpeg" | "image/png" | "image/webp" | null {
  const bytes = decodeBase64(base64);
  if (bytes === null) return null;
  return erkennBildtyp(bytes);
}
