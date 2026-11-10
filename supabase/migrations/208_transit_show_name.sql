-- =============================================================================
-- 208_transit_show_name.sql
-- =============================================================================
-- DER NAME BEI TRANSIT SPARK (BEFUND vom Betreiber, 10.11.2026):
-- "Ich finde aber, dass man bei Transit Spark einstellen können soll, ob
--  der Name für andere sichtbar sein soll oder nicht. Also dann
--  wahrscheinlich für v0.10.1"
--
-- DER SACHVERHALT (live geprüft, nicht vermutet): Im Transit Spark wird der
-- Name HEUTE NICHT übertragen:
--
--   - Die Nah-Liste zeigt nur "vor 3 Minuten gesehen" (das Encounter ist
--     ein anonymer BLE-Token, Migration 081).
--   - `transit_signals` hat KEINE Namensspalte - nur Tokens, Merkmale
--     (`tags`, `self_tags`) und die freie Notiz (`self_note`).
--   - `list_my_soft_pings` gibt nur `messageKey`, `customLine` und die
--     Zeiten zurück - keinen Namen.
--
-- Der Name wird erst sichtbar, wenn ein FUNKE entsteht (dann ist der Chat
-- ohnehin der Ort für den Namen).
--
-- DIE REGEL, DIE DARAUS FOLGERT: Der Name wandert ausschließlich mit dem
-- aktiven Zuwinken (`send_soft_ping`). Wer jemandem zuwinkt, spricht diese
-- Person gezielt an - das ist etwas anderes als "in der Nähe sein".
-- Ein Zuwinken ohne Namen ist nutzlos: der Empfänger kann nicht wissen,
-- wer gewinkt hat.
--
-- DESHALB:
--   - `profiles.transit_show_name` (Default true): Wer seinen Namen beim
--     Zuwinken zeigt, entscheidet das bewusst.
--   - Der Name wird NICHT gespeichert, sondern beim Lesen aufgelöst
--     (`list_my_soft_pings` join't das Profil des Absenders). Damit gilt
--     der Schalter SOFORT - auch wenn er nach dem Winken abgeschaltet
--     wird. Ein gespeicherter Name würde 48 h im Relay liegen, auch wenn
--     der Schalter längst aus ist.
--   - Die Nah-Liste bleibt ANONYM. Wer in der Nähe ist, sieht keine
--     Namen - dafür gibt es das BLUETOOTH-Token-Verfahren (Migration
--     081) mit seinen 45-Minuten-Fenster.
--
-- DIE EHRLICHE GRENZE (steht auch im Text der Einstellung): Der Schalter
-- schützt davor, dass jemand deinen NAMEN sieht, der dir zugewinkt hat.
-- Er schützt NICHT davor, dass dich jemand erkennt, der neben dir steht.
-- Wer das verspricht, verspricht zu viel.
--
-- (Der Schalter selbst ist nur eine Spalte + der Auswertung in der
-- Lesefunktion - das Senden bleibt unveraendert, weil der Name dort
-- gar nicht vorkommt.)
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Die Spalte
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists transit_show_name boolean not null default true;

comment on column public.profiles.transit_show_name is
  'v0.10.1: True = der eigene Name wird beim Transit-Zuwinken angezeigt (Default). False = der Empfaenger sieht nur "Jemand winkt dir zu". Der Name wird beim Lesen aufgeloest, nie gespeichert. Die Nah-Liste bleibt IMMER anonym.';

-- -----------------------------------------------------------------------------
-- 2) Die Lesefunktion: den Namen mitliefern - nur wenn der Absender ihn
--    freigegeben hat.
--
--    BEFUND (10.11.2026): `list_my_soft_pings` gab nur `messageKey` und
--    `customLine` zurueck. Der Name wird jetzt aus dem Profil des
--    Absenders gelesen - und NUR, wenn `transit_show_name` wahr ist.
--
--    Der Join auf `public.profiles` ist unkritisch: die Funktion laeuft
--    als SECURITY DEFINER und gibt ausschliesslich den Namen dessen aus,
--    der DIR zugewinkt hat.
-- -----------------------------------------------------------------------------
create or replace function public.list_my_soft_pings()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', s.id,
             'messageKey', s.message_key,
             'customLine', s.custom_line,
             'createdAt', s.created_at,
             'expiresAt', s.expires_at,
             -- BEFUND (10.11.2026): Der Name kommt NUR, wenn der Absender
             -- ihn freigegeben hat. Sonst bleibt es bei "Jemand winkt dir
             -- zu" - die Anonymitaet ist der Normalzustand.
             'senderName', case
               when coalesce(p.transit_show_name, true) then p.name
               else null
             end
           ) ORDER BY s.created_at DESC), '[]'::jsonb)
  FROM public.transit_soft_pings s
  JOIN public.profiles p ON p.user_id = s.sender
  WHERE s.recipient = auth.uid()
    AND s.status = 'pending'
    AND s.expires_at > now();
$$;

comment on function public.list_my_soft_pings() is
  '208: liefert die Transit-Zuwinke; der Name des Absenders nur, wenn er ihn mit transit_show_name freigegeben hat.';

revoke all on function public.list_my_soft_pings() from public, anon;
grant execute on function public.list_my_soft_pings() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3) BEWEIS (Fail-Fast)
-- -----------------------------------------------------------------------------
do $$
declare
  v_src text;
  v_default text;
  -- Das Muster wird zusammengesetzt, NICHT als Literal geschrieben.
  --
  -- BEFUND (10.11.2026, Push-Reife-Gate): Ein NOT-LIKE-Muster, das auf den
  -- EIGENEN Code trifft, laesst die Funktion beim Apply fehlschlagen -
  -- `v_src` ist der Body von list_my_soft_pings und enthaelt den
  -- Schalternamen selbst. Der Check meldete genau das. Mit der
  -- Zusammensetzung zur Laufzeit trifft das Muster nur den echten Code
  -- (wenn die Funktion den Schalter nicht auswertet) - nicht sich selbst.
  v_muster text := '%' || 'transit_' || 'show_' || 'name' || '%';
begin
  -- (a) Die Spalte existiert.
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'profiles'
       and column_name = 'transit_show_name'
  ) then
    raise exception
      'Sicherheitscheck fehlgeschlagen: profiles.transit_show_name fehlt - der Name laesst sich nicht abschalten.';
  end if;

  -- (b) Der Default ist "an" (der Name wird beim Zuwinken gezeigt).
  select column_default into v_default
    from information_schema.columns
   where table_schema = 'public' and table_name = 'profiles'
     and column_name = 'transit_show_name';

  if v_default is null or v_default not like '%true%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: transit_show_name hat nicht den Default true - der Name waere ohne Zuwinken-Erlaubnis nie sichtbar.';
  end if;

  -- (c) Die Lesefunktion wertet den Schalter aus.
  select p.prosrc into v_src
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'list_my_soft_pings';

  if v_src is null then
    raise exception
      'Sicherheitscheck fehlgeschlagen: list_my_soft_pings() fehlt.';
  end if;

  if v_src not like v_muster then
    raise exception
      'Sicherheitscheck fehlgeschlagen: list_my_soft_pings() wertet den Schalter transit_show_name nicht aus - der Name waere immer sichtbar.';
  end if;

  -- (d) Die Alt-Variante (ohne den Namen) darf nicht mehr aktiv sein:
  --     sonst liefert die App je nach Ueberladung mal mit, mal ohne Name.
  --
  --     Auch hier wird das Muster zur Laufzeit zusammengesetzt: ein
  --     NOT-LIKE, das auf den eigenen Code trifft, wuerde die Migration
  --     beim Apply fehlschlagen lassen (BEFUND 10.11.2026, Push-Reife).
  if exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'list_my_soft_pings'
       and p.prosrc not like v_muster
  ) then
    raise exception
      'Sicherheitscheck fehlgeschlagen: es gibt eine list_my_soft_pings()-Variante ohne den Schalter - der Name waere je nach Aufruf sichtbar oder nicht.';
  end if;
end;
$$;

commit;
