-- =============================================================================
-- 209_transit_name_decision.sql
-- =============================================================================
-- DIE ENTSCHEIDUNG GEHOERT DEM NUTZER (BEFUND vom Betreiber, 10.11.2026):
-- "Die Abfrage über die Entscheidung Name an oder aus soll beim ersten
--  öffnen des Transit Spark screens kommen und dann nachträglich noch
--  änderbar sein. So ist die Entscheidung beim User und er kann bewusst
--  entscheiden."
--
-- DER SACHVERHALT (live geprüft): Migration 208 hat den Schalter
-- `transit_show_name` mit Default TRUE angelegt. Das heisst: die App
-- entscheidet VOR, ob der Name gezeigt wird - der Nutzer bekommt die
-- Entscheidung gar nicht.
--
-- DIE KORREKTUR: Ein ZWEITES Merkmal trennt "wie ist es gerade" von
-- "hat der Nutzer entschieden":
--
--   * transit_show_name     - der aktuelle Wert (AN/AUS). Default true,
--                             damit bis zur Entscheidung nichts kompliziert
--                             ist.
--   * transit_show_name_set - hat der Nutzer bewusst entschieden?
--                             Default FALSE.
--
-- Der Dialog erscheint, solange `transit_show_name_set` false ist. Nach
-- der Entscheidung ist er weg - und der Schalter in der Ansicht bleibt
-- aenderbar (jede Aenderung am Schalter setzt das Flag mit).
--
-- WARUM EIN ZWEITES FLAG und nicht "NULL heisst unentschieden":
-- Ein Schalter braucht einen echten Ja/Nein-Wert. NULL als
-- "unentschieden" wuerde im Schalter als "aus" erscheinen - obwohl das
-- Verhalten bis zur Entscheidung "an" waere. Das waere eine Lüge in der
-- Oberflaeche. Mit dem zweiten Flag bleibt der Schalter ehrlich: er zeigt
-- immer den echten Wert, und das Flag sagt nur, ob der Dialog noch
-- kommen soll.
--
-- DER DIALOG KANN NICHT UMGEHEN WERDEN (das ist Absicht): Die
-- Entscheidung soll bewusst sein. Wer sie nicht treffen will, waehlt
-- "aus" - das ist auch eine bewusste Entscheidung.
--
-- (Der Dialog wird im Client gezeigt - hier steht nur der Zustand, der
-- ihn steuert. Die Entscheidung selbst laeuft ueber updateOwnProfile.)
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Die Spalte
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists transit_show_name_set boolean not null default false;

comment on column public.profiles.transit_show_name_set is
  'v0.10.1: Hat der Nutzer bewusst entschieden, ob sein Name beim Transit-Zuwinken gezeigt wird? false = der Dialog kommt beim naechsten Oeffnen des Transit-Radars. Wird bei jeder Aenderung am Schalter mitgesetzt.';

-- -----------------------------------------------------------------------------
-- 2) BEWEIS (Fail-Fast)
-- -----------------------------------------------------------------------------
do $$
declare
  v_default text;
  v_nulls int;
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'profiles'
       and column_name = 'transit_show_name_set'
  ) then
    raise exception
      'Sicherheitscheck fehlgeschlagen: profiles.transit_show_name_set fehlt - der Dialog kaeme nicht.';
  end if;

  select column_default into v_default
    from information_schema.columns
   where table_schema = 'public' and table_name = 'profiles'
     and column_name = 'transit_show_name_set';

  if v_default is null or v_default not like '%false%' then
    raise exception
      'Sicherheitscheck fehlgeschlagen: transit_show_name_set hat nicht den Default false - der Dialog wuerde bei neuen Konten ausbleiben.';
  end if;

  -- Die Spalte darf nicht NULL sein: "unentschieden" heisst false,
  -- nicht unbestimmt.
  select count(*) into v_nulls
    from information_schema.columns
   where table_schema = 'public' and table_name = 'profiles'
     and column_name = 'transit_show_name_set'
     and is_nullable = 'YES';

  if v_nulls > 0 then
    raise exception
      'Sicherheitscheck fehlgeschlagen: transit_show_name_set ist nullable - "unentschieden" muss false sein, nicht unbestimmt.';
  end if;
end;
$$;

commit;
