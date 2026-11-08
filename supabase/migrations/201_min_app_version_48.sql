-- =============================================================================
-- 201_min_app_version_48.sql
-- =============================================================================
-- Mindest-App-Version auf Build 48 (Sicherheitsupdate eMudhra).
--
-- BEFUND (08.11.2026): Advisory GHSA-frr6-h895-5pxp (High). Die
-- privaten Schluessel von acht Zwischenzertifikaten der CA eMudhra
-- wurden im Oktober 2026 oeffentlich als kompromittiert gemeldet.
-- `dart:io` prueft auf Android mit einem EINGEBAUTEN BoringSSL und
-- liest die Sperrliste des Betriebssystems NICHT - ein Angreifer im
-- Netzpfad kann damit ein gefaelschtes TLS-Zertifikat vortaeuschen.
--
-- Der Fix steckt in der BINARY: Flutter 3.47.9 / Dart 3.13.7
-- (Build 48). Ein SDK-Update allein genuegt nicht - der Build muss
-- neu verteilt werden. Bis dahin laeuft auf jedem alten Build ein
-- Client im Umlauf, der die Luecke nicht schliesst.
--
-- WARUM DAS GATE (und nicht nur der Server):
--   Der Server kann die Luecke nicht schliessen - ein MITM passiert
--   zwischen Geraet und Server, also vor dem Server. Nur ein Build,
--   der die Sperrliste kennt, schliesst sie. Dieses Gate ist der
--   einzige Weg, die alten Builds zuverlaessig zu den Nutzern
--   durchzuleiten.
--
-- Gegenrichtung geprueft: Die serverseitigen Massnahmen (Migration
-- 200 - die drei Datenwege laufen ueber den gepinnten Client mit
-- leerem Root-Store) wirken sofort und unabhaengig vom Build. Das
-- Gate schliesst die Luecke auf der CLIENT-SEITE - es verhindert,
-- dass ein alter Build die Sperre umgeht, weil er sie gar nicht
-- erst kennt. Beides wird gebraucht.
--
-- ZUR REICHWEITE: Wer den Hinweis sieht, kann ueber "Trotzdem
-- fortfahren" trotzdem weitermachen (der Screen hat einen
-- onDismiss). Der Server blockiert dann die betroffenen RPCs. Das
-- ist Absicht: Ein Update-Zwang ohne Ausnahme waere ein
-- Ausfall, ein Update ohne Hinweis auf den Grund fuehrt dazu, dass
-- niemand updatet - und genau das waere der schlechtere Fall.
--
-- Schemahinweis: `app_config` hat ausschliesslich (key, value) - 034:52.
-- Es gibt KEINE `description`-Spalte, die Erklaerung gehoert hierher.
-- =============================================================================

INSERT INTO public.app_config (key, value)
VALUES ('min_app_version_build', '48')
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value;

-- BEWEIS (Fail-Fast): der Wert muss wirklich 48 sein. Sonst laeuft die
-- Migration durch, obwohl ein ALTER-Trigger oder ein Schreibfehler ihn
-- zurueckgesetzt haette - dann wuerden weiterhin die alten Clients
-- bedient, deren Zertifikatspruefung die gesperrten Zwischenzertifikate
-- noch akzeptiert.
DO $$
DECLARE
  v_val text;
BEGIN
  SELECT value INTO v_val FROM public.app_config WHERE key = 'min_app_version_build';
  IF v_val IS DISTINCT FROM '48' THEN
    RAISE EXCEPTION 'Sicherheitscheck fehlgeschlagen: min_app_version_build ist "%", erwartet "48".', v_val;
  END IF;
  RAISE NOTICE 'min_app_version_build ist jetzt 48 - aeltere Builds sehen den Update-Hinweis.';
END;
$$;
