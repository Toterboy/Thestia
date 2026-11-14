-- =============================================================================
-- 217_dating_hour_gender_mix_symmetric.sql
-- =============================================================================
-- DER BETREIBER (14.11.2026): "Bei Dating Hour irgendwie umsetzen, dass von
-- beiden Geschlechtern welche in dem Event sind, wenn alle Hetero."
--
-- WAS DIESE MIGRATION RICHTET: Migration 216 hat die Regel eingebaut, aber
-- die Gegenseite nicht mitgeprueft. Geprueft wurde nur, was DER SUCHENDE
-- will - was der GEFUNDENE will, zaehlte nicht. Das ist bei einer
-- Paarung falsch: sie muss beidseitig sein (wie das Alter schon immer
-- war - siehe age_compatible_bidirectional).
--
-- DER FEHLER, DEN DAS BEISPIEL ZEIGT:
--
--   Eine Frau, die ausdruecklich nur Frauen sucht (lesbisch), und ein
--   Mann, der nichts ausgewaehlt hat, wurden von 216 als passend
--   eingestuft - sie will ihn nicht, er passt nur nicht zu ihr.
--
-- DIE LOESUNG: Beide Seiten werden ueber ihre "akzeptierten Gruppen"
-- geprueft:
--
--   * ausdruecklich NUR das eigene Geschlecht gewaehlt -> nur dieses,
--   * ausdruecklich NUR das andere Geschlecht gewaehlt -> nur dieses
--     (das ist der Hetero-Fall des Betreibers: sind alle hetero, besteht
--     das Event aus Maennern UND Frauen),
--   * ausdruecklich "Alle" gewaehlt -> alle gewaehlten Gruppen,
--   * nichts ausgewaehlt (der Vorgabe-Stand) -> alles ausser der eigenen
--     Gruppe: das Event ist ein hetero Event.
--
-- Ein Paar passt, wenn BEIDE den anderen akzeptieren.
--
-- Migration 216 bleibt unveraendert (sie ist angewandt); diese Migration
-- ersetzt nur die zwei Hilfsfunktionen. Die Paarungsrunde selbst
-- (match_dating_hour_round) ruft dh_gender_compatible auf und bekommt
-- damit automatisch die neue Regel.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Die Gruppen, bei denen ein Nutzer ein Gegenueber akzeptiert
-- -----------------------------------------------------------------------------

create or replace function public.dh_accepts(p_gender text, p_prefs text[])
 returns text[]
 language plpgsql
 immutable
 set search_path to ''
as $$
declare
  v_own text;
  v_groups text[];
  v_all text[] := array['m','w','d']::text[];
begin
  v_own := public.dh_gender_group(p_gender);
  v_groups := public.dh_wanted_groups(p_prefs);

  -- AUSDRUECKLICHE WAHL: sie gilt genau so (und nur so).
  if array_length(v_groups, 1) is not null then
    return v_groups;
  end if;

  -- NICHTS GEWAEHLT (der Vorgabe-Stand): das Event ist ein hetero Event.
  -- Wer 'm' ist, akzeptiert 'w' (und 'd'), wer 'w' ist, akzeptiert 'm'
  -- (und 'd'), wer 'd' ist, akzeptiert 'm' und 'w'.
  if v_own is null then
    return v_all;
  end if;
  return array_remove(v_all, v_own);
end;
$$;

comment on function public.dh_accepts(text, text[]) is
  'v0.10.2: Die Geschlechtsgruppen, bei denen dieser Nutzer ein Gegenueber akzeptiert. Ausdrueckliche Wahl gilt genau so; nichts gewaehlt bedeutet: hetero Event.';

revoke all on function public.dh_accepts(text, text[]) from public, anon, authenticated;
grant execute on function public.dh_accepts(text, text[]) to service_role;

-- -----------------------------------------------------------------------------
-- 2) Die beidseitige Pruefung
-- -----------------------------------------------------------------------------

create or replace function public.dh_gender_compatible(
  a_gender text,
  a_prefs text[],
  b_gender text,
  b_prefs text[]
)
 returns boolean
 language plpgsql
 immutable
 set search_path to ''
as $$
declare
  v_a_group text;
  v_b_group text;
  v_a_accepts text[];
  v_b_accepts text[];
begin
  v_a_group := public.dh_gender_group(a_gender);
  v_b_group := public.dh_gender_group(b_gender);

  -- Unbekanntes Geschlecht: keine Einschraenkung. Lieber einen Partner
  -- finden als niemanden.
  if v_a_group is null or v_b_group is null then
    return true;
  end if;

  v_a_accepts := public.dh_accepts(a_gender, a_prefs);
  v_b_accepts := public.dh_accepts(b_gender, b_prefs);

  -- BEIDSEITIG: jeder muss den anderen akzeptieren (wie beim Alter).
  return (v_b_group = any(v_a_accepts)) and (v_a_group = any(v_b_accepts));
end;
$$;

comment on function public.dh_gender_compatible(text, text[], text, text[]) is
  'v0.10.2: Passen zwei Nutzer fuer die Dating Hour zusammen? Beidseitig. Ausdrueckliche Wahl hat Vorrang; nichts gewaehlt bedeutet: hetero Event.';

revoke all on function public.dh_gender_compatible(text, text[], text, text[]) from public, anon, authenticated;
grant execute on function public.dh_gender_compatible(text, text[], text, text[]) to service_role;

commit;
