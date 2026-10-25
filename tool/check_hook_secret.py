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


def kandidaten(secret):
    """Alle moeglichen HMAC-Schluesselbytes - wie die Function sie bildet."""
    out = []
    trimmed = secret[6:] if secret.startswith('whsec_') else secret
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
    out.append(('roh', secret.encode('utf-8')))
    return out


def signiere(secret, wid, ts):
    msg = wid.encode() + b'.' + ts.encode() + b'.' + BODY
    for name, key in kandidaten(secret):
        sig = base64.b64encode(
            hmac.new(key, msg, hashlib.sha256).digest()).decode()
        yield name, 'v1,' + sig


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

    # Das Dashboard zeigt den Wert teils mit "v1,"-Praefix.
    if secret.startswith('v1,'):
        secret = secret[3:].strip()

    print(f'Geprueftes Secret: {len(secret)} Zeichen, '
          f'Praefix whsec_: {secret.startswith("whsec_")}')

    wid = 'msg_secret_check'
    ts = str(int(time.time()))

    for name, sig in signiere(secret, wid, ts):
        st, txt = ruf({
            'Content-Type': 'application/json',
            'webhook-id': wid,
            'webhook-timestamp': ts,
            'webhook-signature': sig,
        })
        print(f'  Ableitung {name:7} -> HTTP {st}  {txt[:80]}')

    print()
    print('Deutung:')
    print('  401 bei ALLEN Ableitungen -> das Secret passt NICHT zum')
    print('    Function-Secret. Im Dashboard den Hook-Secret anzeigen und')
    print('    mit folgendem Befehl setzen:')
    print('      supabase secrets set HOOK_SECRET="<Dashboard-Wert>"')
    print('  500 -> Fehler in der Function (Log in Supabase Dashboard')
    print('    ansehen: Edge Functions -> send-confirmation-email -> Logs')
    print('  200/4xx mit JSON (nicht "Unauthorized") -> die Signatur passt.')
    print('    Dann ist die Kette Dashboard -> GoTrue -> Function in Ordnung.')
    return 0


if __name__ == '__main__':
    sys.exit(main())