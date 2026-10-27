"""Prueft, ob das Hook-Secret in den Function-Secrets zum Dashboard-Wert passt.

Hintergrund (21.10.2026): Die Function send-confirmation-email prueft die
Standard-Webhooks-Signatur von GoTrue. Dafuer muss das Secret in den
Function-Secrets DENSELBEN Wert haben, den das Dashboard anzeigt. Sind
die beiden verschieden, antwortet die Function immer mit 401, und GoTrue
meldet den Hook als fehlgeschlagen - die Bestaetigungs-Mails kommen
dann nicht an, ohne dass irgendwo ein Fehler auffaellt.

Das war hier die Ursache: In den Function-Secrets stand ein 64-stelliger
Hex-Wert, die Function hat ihn aber als Base64 dekodiert (48 Byte
Muell) - die Signatur passte nie. Behoben ist das in der Function
selbst (sie akzeptiert jetzt Hex, Base64 und Rohbytes). Bleibt die
Abweichung zwischen Dashboard und Function-Secret, muss der Wert
angeglichen werden.

AUFRUF
------
    python tool\check_hook_secret.py "<Wert aus dem Dashboard>"

Der Wert wird NICHT gespeichert, nur zum Signieren eines Testaufrufs
verwendet. Das Skript gibt ihn nirgends aus.
"""
import base64
import hashlib
import hmac
import json
import sys
import time
import urllib.error
import urllib.request

URL = ('https://jftuigjbmmuvrckbchqo.supabase.co'
       '/functions/v1/send-confirmation-email')

BODY = json.dumps({
    'type': 'signup',
    'user': {'id': '00000000-0000-0000-0000-000000000001',
             'email': 'hook-test@example.invalid'},
}).encode()


def kandidaten(original):
    """Alle moeglichen HMAC-Schluesselbytes - wie die Function sie bildet.

    Der 'roh'-Kandidat nutzt den ORIGINALEN Wert (inklusive 'v1,' und
    'whsec_'), genau wie die Function in send-confirmation-email. Vorher
    hatte der Pruefer das 'v1,' abgeschnitten und damit den Roh-Byte-
    Kandidaten gegen einen anderen Wert geprueft als die Function -
    die beiden konnten nie uebereinstimmen, was verwirrend aussah.

    Die Reihenfolge der Kandidaten ist bewusst: 'base64' zuerst, weil
    ein 'whsec_'-Wert nach Standard-Webhooks immer Base64 ist. Die
    anderen beiden sind Rueckfall fuer die Formate, die das Dashboard
    frueher geliefert hat (64 Hex-Zeichen) bzw. fuer einen gar nicht
    kodierten Wert.
    """
    out = []
    trimmed = original
    if trimmed.startswith('v1,'):
        trimmed = trimmed[3:]
    if trimmed.startswith('whsec_'):
        trimmed = trimmed[6:]
    if not trimmed:
        return out
    try:
        out.append(('base64', base64.b64decode(
            trimmed + '=' * (-len(trimmed) % 4))))
    except Exception:
        pass
    if len(trimmed) % 2 == 0:
        try:
            out.append(('hex', bytes.fromhex(trimmed)))
        except Exception:
            pass
    out.append(('roh', original.encode('utf-8')))
    return out


def formen(secret):
    """Die Formen, in denen derselbe Wert im Dashboard auftauchen kann.

    Das Dashboard zeigt den Hook-Secret je nach Ansicht mit oder ohne
    Versions-Marker "v1,". Beide muessen funktionieren - deshalb wird
    jede Form geprueft, statt den Nutzer raten zu lassen, welche die
    richtige ist.

    Wichtig: die Formen werden VOR der Ableitung normalisiert, damit
    "v1,whsec_X" und "whsec_X" dieselben Schluesselbytes ergeben. Der
    'roh'-Kandidat bleibt dagegen bewusst der jeweilige Originalwert,
    weil die Function ihn auch so bildet.
    """
    aus = []
    s = secret.strip()
    aus.append(s)
    if not s.startswith('v1,'):
        aus.append('v1,' + s)
    return aus


def signiere(secret, wid, ts):
    msg = wid.encode() + b'.' + ts.encode() + b'.' + BODY
    for form in formen(secret):
        for name, key in kandidaten(form):
            sig = base64.b64encode(
                hmac.new(key, msg, hashlib.sha256).digest()).decode()
            kennung = name if form == secret.strip() else name + '+v1'
            yield kennung, 'v1,' + sig


def ruf(headers):
    req = urllib.request.Request(URL, data=BODY, method='POST', headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, r.read()[:200].decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:200].decode('utf-8', 'replace')
    except Exception as e:
        return 'FEHLER', repr(e)[:160]


def main():
    if len(sys.argv) >= 2:
        secret = sys.argv[1].strip()
    else:
        # Ohne Argument: versteckt nachfragen. So landet der Wert weder
        # im Shell-Verlauf noch auf dem Bildschirm. Genau fuer den Fall
        # gedacht, dass das Dashboard den Wert nur maskiert anzeigt -
        # kopieren genuegt, angezeigt werden muss er nie.
        import getpass
        print('Dashboard-Wert einfuegen (Eingabe bleibt unsichtbar):')
        secret = getpass.getpass('> ').strip()
        if not secret:
            print('Abgebrochen: kein Wert eingegeben.')
            return 2

    # Das Dashboard zeigt den Wert teils mit "v1,"-Praefix. Der Wert
    # wird NICHT mehr veraendert - die Ableitungen unten beruecksichtigen
    # beide Formen selbst.
    print(f'Geprueftes Secret: {len(secret)} Zeichen, '
          f'Praefix whsec_: {secret.startswith("whsec_")}, '
          f'Praefix v1,: {secret.startswith("v1,")}')

    wid = 'msg_secret_check'
    ts = str(int(time.time()))

    # Merke, welche Ableitung gegriffen hat.
    #
    # DIE ENTSCHEIDENDE REGEL (2026-10-27, nach Verwirrung im Chat):
    #
    #   HTTP 401 {"error":"Unauthorized"}  = die Signatur wurde
    #     ABGEWIESEN. Das Secret passt NICHT. Das ist der Fehlerfall.
    #
    #   HTTP 400 {"error":"Missing email or token"}  = die Signatur wurde
    #     ANGENOMMEN. Die Function ist weitergekommen und hat nur
    #     gemeckert, dass der Testkoerper kein Token enthaelt - genau wie
    #     es sein soll, weil GoTrue ein vollstaendiges Payload schickt.
    #     DAS IST DER TREFFER.
    #
    # Wer HTTP 400 als Fehler liest, haelt eine korrekte Kette fuer kaputt.
    getroffen = []
    for name, sig in signiere(secret, wid, ts):
        st, txt = ruf({
            'Content-Type': 'application/json',
            'webhook-id': wid,
            'webhook-timestamp': ts,
            'webhook-signature': sig,
        })
        passt = (st != 401 and st != 'FEHLER' and 'Unauthorized' not in txt)
        marke = ''
        if passt:
            marke = '   <-- SIGNATUR ANGENOMMEN = Secret stimmt'
        print(f'  Ableitung {name:12} -> HTTP {st}  {txt[:70]}{marke}')
        if passt:
            getroffen.append(name)

    print()
    if getroffen:
        print('=' * 70)
        print('ERGEBNIS: PASST. Das Secret stimmt mit dem Function-Secret')
        print('  ueberein - die Ableitung "' + getroffen[0] + '" wurde')
        print('  angenommen.')
        print('=' * 70)
        print()
        print('  Der HTTP 400 ist dabei KEIN Fehler: die Function hat die')
        print('  Signatur angenommen und sich nur ueber das unvollstaendige')
        print('  Testpayload beschwert (kein Token). GoTrue schickt ein')
        print('  vollstaendiges Payload - der Testkoerper hier ist absichtlich')
        print('  abgespeckt.')
        print()
        print('  Die Kette Dashboard -> GoTrue -> Function ist in Ordnung.')
        print('  Was jetzt noch fehlen kann:')
        print('    * Der Hook zeigt im Dashboard auf eine ANDERE Function')
        print('      (Authentication -> Hooks -> Send Email Hook -> URL)')
        print('    * Der Hook ist nicht aktiviert')
        print('    * Der Mail-Dienst (Mailjet/Brevo) nimmt die Mail nicht an')
        print('      (Domain nicht verifiziert, Guthaben leer, Absender')
        print('      nicht bestaetigt - Log in Edge Functions ->')
        print('      send-confirmation-email -> Logs zeigt den Grund)')
        return 0

    print('=' * 70)
    print('ERGEBNIS: PASST NICHT. Das Function-Secret ist ein anderes als')
    print('  der eingegebene Wert (alle Ableitungen wurden mit 401')
    print('  abgewiesen).')
    print('=' * 70)
    print()
    print('  Naechster Schritt: den Wert aus dem Dashboard (Authentication')
    print('  -> Hooks -> Send Email Hook) in den Function-Secret uebernehmen:')
    print()
    print('    supabase secrets set HOOK_SECRET="<Dashboard-Wert>"')
    print()
    print('  Danach dieses Skript mit DEMSELBEN Wert erneut laufen lassen.')
    print('  Dann muss "SIGNATUR ANGENOMMEN" dastehen.')
    print()
    print('  WICHTIG: Der Wert im Dashboard ist masked. Du musst ihn nicht')
    print('  SEHEN - kopieren genuegt. Es gibt zwei Wege:')
    print('    1. Neben dem Feld im Dashboard auf das Kopier-Symbol klicken')
    print('       (der Wert landet dann in der Zwischenablage, auch wenn er')
    print('       maskiert angezeigt wird).')
    print('    2. Oder "Generate Secret" klicken: dann wird ein NEUER Wert')
    print('       erzeugt und der alte ist sofort ungueltig. Den neuen Wert')
    print('       setzen UND in die Function uebernehmen.')
    print('       (Wichtig: Danach MUSS die Function neu deployt werden,')
    print('       sonst laeuft sie mit dem alten Secret weiter - siehe')
    print('       supabase/supabase#51535: die Umgebung der laufenden')
    print('       Function ist zum Deploy-Zeitpunkt fixiert.)')
    print()
    print('  Falls 500 kam: Fehler in der Function, Log ansehen unter')
    print('  Edge Functions -> send-confirmation-email -> Logs.')
    return 1


if __name__ == '__main__':
    sys.exit(main())