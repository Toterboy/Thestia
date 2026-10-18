# tool/set_admin_flag.sql
--
-- Setzt das Admin-Flag fuer EINEN Nutzer in der Datenbank.
--
-- WANN DAS NOETIG IST
-- --------------------
-- Der Admin-Bereich hat zwei unabhaengige Puerfungen:
--
--   1. CLIENT  isCurrentUserAdmin() vergleicht die eingeloggte
--      User-ID mit AppConstants.adminUserId. adminUserId kommt aus
--      --dart-define=ADMIN_UUID. In der OEFFENTLICHEN APK ist dieser
--      Wert bewusst leer, also ist diese Pruefung dort immer falsch
--      und der Screen leitet sofort auf die Startseite um.
--
--   2. SERVER  is_current_user_admin() liest profiles.is_admin fuer
--      auth.uid(). Steht dort false, leitet auch die ADMIN-APK ab.
--
-- Wer also die richtige APK hat und trotzdem abgeleitet wird, hat die
-- zweite Huerde nicht genommen: das Flag ist in der Datenbank nicht
-- gesetzt. Genau das ist der Fall, wenn der Admin-Bereich sich
-- "direkt wieder schliesst".
--
-- ANWENDUNG
-- ---------
-- Supabase Dashboard -> SQL Editor -> dieses Skript anpassen und
-- ausfuehren. Zuerst die UUID PRUEFEN, dann setzen:
--
--   1. SELECT ... (unten)
--
--   2. Erst wenn dort dein Konto steht, UPDATE ausfuehren. Das
--      profiles-Schema hat genau eine user_id - ein Treffer ist die
--      Bedingung, nicht ein Zufall.
--
-- ZUM JOIN MIT auth.users: `profiles` hat KEINE email-Spalte. Die
-- E-Mail steht ausschliesslich in auth.users; profiles fuehrt name,
-- user_id, is_admin und die Profildaten. Ein Versuch mit
-- "SELECT user_id, email, is_admin FROM profiles" endet deshalb mit
--
--     ERROR: 42703: column "email" does not exist
--
-- Das ist kein Tippfehler im Aufruf, sondern der Aufbau des Schemas.
-- Fuer die Anzeige des Kontos wird deshalb gejoint.
--
-- Es wird hier bewusst KEINE UPDATE-Anweisung mitgeschickt, die auf
-- Vornamen oder E-Mail matcht: wer dieselbe E-Mail im Test und im
-- echten Betrieb hat, wuerde sonst beide Konten zum Admin machen.

SELECT p.user_id,
       p.name,
       p.is_admin,
       u.email,
       u.email_confirmed_at
FROM public.profiles p
JOIN auth.users u ON u.id = p.user_id
WHERE p.user_id = 'HIER-DIE-ADMIN-UUID-EINTRAGEN';

-- Nach dem Pruefen auskommentieren und ausfuehren:
--
-- UPDATE public.profiles
-- SET is_admin = true
-- WHERE user_id = 'HIER-DIE-ADMIN-UUID-EINTRAGEN';
--
-- Rueckweg (falls versehentlich zu viel Admin wurde):
--
-- UPDATE public.profiles
-- SET is_admin = false
-- WHERE user_id = 'HIER-DIE-ADMIN-UUID-EINTRAGEN';