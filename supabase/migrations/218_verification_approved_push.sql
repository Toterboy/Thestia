-- =============================================================================
-- 218_verification_approved_push.sql
-- =============================================================================
-- DIE AUFGABE (Betreiber, "Benachrichtigung bei Freigabe der Verifizierung"):
-- Der Nutzer soll ERFAHREN, dass seine Alterspruefung freigegeben wurde -
-- auch wenn die App gerade nicht offen ist. Bisher gab es nur eine lokale
-- Meldung bei einem Statuswechsel in der App (also nur, wenn er zufaellig
-- mit der App arbeitet).
--
-- DER WEG (dieser Block): Ein Trigger auf public.profiles feuert, wenn der
-- Verifikationsstatus in den freigegebenen Zustand WEchselt, und ruft die
-- Edge Function notify-user (interne Variante, mit dem Vault-Secret
-- 'thestia_internal_secret') - genau das Muster der uebrigen Push-Trigger
-- (Migration 146, notify_push_trigger).
--
-- "NUR BEIM UEBERGANG": Der Trigger feuert nicht bei jedem UPDATE der
-- Profiltabelle, sondern nur, wenn der Zustand von "nicht freigegeben" auf
-- "freigegeben" wechselt. Sonst wuerde jedes Profil-Update (z. B. ein
-- Like-Zaehler) den Nutzer erneut benachrichtigen.
--
-- DER TEXT IST SERVSEITIG: Wie bei allen anderen Pushes kommt er nicht
-- vom Client (sonst waere es Push-Phishing). Die App holt sich den Text
-- aus der notification-Sektion des Pushs; der Fallback-Text in der App
-- ('Deine Alterspruefung wurde freigegeben.') greift nur, wenn der Server
-- keinen mitliefert.
--
-- DIE ZUSTANDSWERTE (Migration 144/155):
--   profiles.verification_status: none | pending | pending_minor |
--                                  approved | rejected | auto
--   profiles.is_verified: boolean (die Freigabe selbst)
--
-- BEI DER ABLEHNUNG: kein Push. Eine Ablehnung ist kein Freigabe-Ereignis -
-- und der Nutzer sieht sie ohnehin in der App (der Hinweis auf "Aktuelles"
-- erklaert den Status). Verschwiegen wird nur die positive Meldung.
--
-- FAIL-CLOSED: Fehlt das Vault-Secret, geht KEIN Push raus (die Migration
-- 146 hat denselben Schutz). Der Trigger darf den Review nie verhindern -
-- er meldet nur.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Die Trigger-Funktion
-- -----------------------------------------------------------------------------

create or replace function public.notify_verification_approved()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_url text;
  v_secret text := null;
  v_war_freigegeben boolean;
  v_ist_freigegeben boolean;
begin
  -- Ist ueberhaupt eine Freigabe entstanden?
  v_ist_freigegeben :=
    coalesce(new.is_verified, false) is true
    or coalesce(new.verification_status, '') = 'approved';

  -- War es vorher schon freigegeben? Dann ist das kein neues Ereignis.
  v_war_freigegeben :=
    coalesce(old.is_verified, false) is true
    or coalesce(old.verification_status, '') = 'approved';

  if v_ist_freigegeben is not true then
    return new;
  end if;
  if v_war_freigegeben is true then
    return new;
  end if;

  -- Secret aus Vault lesen. Fehlt es, wird KEIN Push versendet
  -- (fail-closed fuer das Feature, sicher gegen Missbrauch).
  begin
    select decrypted_secret into v_secret
    from vault.decrypted_secrets
    where name = 'thestia_internal_secret'
    limit 1;
  exception when others then
    v_secret := null;
  end;

  if v_secret is null or v_secret = '' then
    raise warning
      'notify_verification_approved: Secret thestia_internal_secret fehlt in Vault - kein Push-Versand.';
    return new;
  end if;

  v_url := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/notify-user';

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-thestia-internal', v_secret
    ),
    body := jsonb_build_object(
      'kind', 'verification',
      'target_user_id', new.user_id,
      'title', 'Alles geprueft!',
      'body', 'Deine Alterspruefung wurde freigegeben - alle Modi sind jetzt offen.'
    )
  );
  return new;
end;
$$;

comment on function public.notify_verification_approved() is
  'Push bei Freigabe der Alterspruefung (Migration 218). Feuert nur beim '
  'UEBERGANG in den freigegebenen Zustand. Ruft die Edge Function '
  'notify-user intern (Header ''x-thestia-internal'', Vault-Secret '
  '''thestia_internal_secret'') auf. Fehlt das Secret, geht kein Push raus.';

-- -----------------------------------------------------------------------------
-- 2) Der Trigger
-- -----------------------------------------------------------------------------

drop trigger if exists trg_notify_verification_approved on public.profiles;

create trigger trg_notify_verification_approved
after update of verification_status, is_verified on public.profiles
for each row
execute function public.notify_verification_approved();

commit;
