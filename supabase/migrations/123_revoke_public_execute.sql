-- =============================================================================
-- 123_revoke_public_execute.sql
-- =============================================================================
-- Sicherheitsaudit 2026-09-26: REVOKE-Sweep fuer nie bereinigte Functions.
--
-- BEFUND: In allen bisherigen Migrationen wurde EXECUTE nur von der Rolle
-- `authenticated` entzogen:
--
--   ALTER DEFAULT PRIVILEGES IN SCHEMA public
--     REVOKE EXECUTE ON FUNCTIONS FROM authenticated;   -- 040:388, 061:46
--
-- Der Postgres-DEFAULT-Grant bleibt aber `EXECUTE ... TO PUBLIC`, und `PUBLIC`
-- umfasst `anon` MIT. Ueber PostgREST (`POST /rest/v1/rpc/<name>`) waren
-- deshalb 27 Functions fuer die Rolle `anon` aufrufbar - ohne jedes JWT.
--
-- KRITISCHSTES EINZELBEISPIEL: `quiz_shuffle_for_match` ist eine reine,
-- deterministische Permutationsfunktion. Ein angemeldeter Angreifer konnte
-- ueber sie den korrekten Antwortindex des persoenlichen Quiz ermitteln, indem
-- er alle 4! = 24 Permutationen der erhaltenen Optionsliste durchprobte. Damit
-- war `unlock_level = 2` und damit der AES-Schluessel fuer SCHARFE Profilfotos
-- (`match-media`) erreichbar - ohne eine einzige richtige Antwort.
--
-- Die Helfer werden nur intern von `start_quiz_attempt` / `submit_quiz_answer`
-- aufgerufen. Beide sind SECURITY DEFINER, laufen als Owner und behalten
-- EXECUTE. Sie werden deshalb auch von `authenticated` entzogen - das
-- schliesst den Exploit vollstaendig.
--
-- DREI FALLSTRICKE, die dieser Entwurf beruecksichtigt:
--
-- 1) `REVOKE ... FROM anon` GENUEGT NICHT. Jede Rolle ist implizit Mitglied
--    der Pseudo-Rolle PUBLIC. Wird die Berechtigung ueber PUBLIC vererbt,
--    bleibt sie nach einem Rollen-Revoke bestehen - der erste Push-Versuch hat
--    das aufgedeckt: nach `REVOKE ... FROM anon` waren 13 Trigger-/Admin-
--    Helfer weiterhin fuer anon aufrufbar. Es heisst `FROM PUBLIC`.
--
-- 2) `quiz_pick_personalized` hat ZWEI Overloads (6 Argumente aus Migration
--    086, 7 Argumente aus 087/089). Eine REVOKE-Liste pro Signatur hat beim
--    ersten Push genau die 6-Arg-Version uebersehen. Deshalb wird hier
--    dynamisch ueber `pg_proc.oid::regprocedure` aufgeloest.
--
-- 3) `p.proname <> ALL (ARRAY[...])` lehnt die echte Datenbank mit
--    "syntax error at or near ]" ab, obwohl pglast die Datei als gueltig
--    bewertet. Die Allowlist steht deshalb als `string_to_array(...)`.
--
-- ROLLEN:
--   anon          -> nichts. PostgREST darf ohne JWT keine Function.
--   authenticated-> nur die Allowlist (84 Eintraege).
--   service_role  -> alles (nur mit dem Secret-Key erreichbar; haelt
--                    Studio, Admin-Tools und Edge Functions).
--
--Die Allowlist umfasst die 70 RPCs, die der App-Code tatsaechlich
-- aufruft, plus die Functions, die in RLS-USING/WITH CHECK- und
-- View-Definitionen ausgewertet werden. Letztere werden beim Planen gegen den
-- AUFRUFENDEN User geprueft - ohne EXECUTE bricht dort jede Query. Alles
-- andere verliert die Berechtigung, darunter auch `force_photo_moderation_status()`:
-- waere das fuer authenticated aufrufbar, koennte ein Nutzer per RPC den
-- eigenen Moderationsstatus selbst setzen.
-- =============================================================================

-- Zugriff fuer kuenftige Functions: nur explizit GECHTEN. Das ist die
-- Ursache der Luecke und wird hier global geschlossen.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO authenticated;

-- service_role behaelt alles: die Rolle ist nur mit dem Secret-Key erreichbar
-- und wird von Studio, Admin-Tools und den Edge Functions benutzt.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- -----------------------------------------------------------------------------
-- 1) Allowlist: anon verliert PUBLIC, authenticated bekommt es explizit.
--    Das GRANT ist noetig, damit `authenticated` nicht von der PUBLIC-Vererbung
--    abhaengt, sondern eine eigene ACL-Zeile hat.
-- -----------------------------------------------------------------------------
DO $allow$
DECLARE
  r    record;
  v_ok text[];
BEGIN
  v_ok := string_to_array($names$
accept_soft_ping,acknowledge_photo_appeal,admin_decide_photo_appeal,admin_get_dating_hour_min_participants,admin_list_auto_verifications,admin_list_banned_emails,admin_list_bug_reports,admin_list_pending_verifications,admin_list_photo_appeals,admin_list_user_reports,admin_resolve_user_report,admin_set_dating_hour_min_participants,age_compatible,age_compatible_bidirectional,answer_spice_question,assert_age_compatible,block_user,check_email_ban_status,consume_rate_limit,cool_match,create_match_if_mutual,end_match,find_user_by_code,get_current_or_next_dating_hour,get_dating_hour_min_participants,get_dating_hour_participant_count,get_find_match_candidates,get_last_dating_hour_preferences,get_match_partner_profile,get_match_quiz_state,get_meet_intent,get_my_active_dating_hour_session,get_my_active_random_chat,get_my_photo_appeal,get_nearby_profiles,get_public_profile,get_public_profiles,get_random_chat_session,get_spice_questions,get_user_mood,hide_match,is_current_user_admin,is_email_banned,join_dating_hour,join_random_chat,leave_dating_hour,leave_random_chat,like_user,list_blocked_users,list_my_likes_pending,list_my_matches_with_state,list_my_reports,list_my_soft_pings,list_received_likes_pending,match_bucket_add,match_bucket_delete,match_bucket_items,match_bucket_toggle,match_proximity_spark,profile_age,profile_discovery_visible,profile_discovery_visible_full,profile_distance_km,profile_to_jsonb,record_dating_hour_decision,register_chat_image_hash,relay_ack,relay_fetch,relay_store,respark_match,respond_to_like,save_dating_hour_preferences,send_soft_ping,session_meets_auth_requirements,set_match_kind,set_meet_intent,set_user_mood,start_quiz_attempt,submit_photo_appeal,submit_quiz_answer,submit_report,transit_presence_heartbeat,transit_presence_leave,unblock_user
$names$, ',');

  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname::text = ANY (v_ok)
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  END LOOP;
END;
$allow$;

-- -----------------------------------------------------------------------------
-- 2) Alles ausserhalb der Allowlist: PUBLIC, anon UND authenticated.
-- -----------------------------------------------------------------------------
DO $sweep$
DECLARE
  r    record;
  v_ok text[];
BEGIN
  v_ok := string_to_array($names$
accept_soft_ping,acknowledge_photo_appeal,admin_decide_photo_appeal,admin_get_dating_hour_min_participants,admin_list_auto_verifications,admin_list_banned_emails,admin_list_bug_reports,admin_list_pending_verifications,admin_list_photo_appeals,admin_list_user_reports,admin_resolve_user_report,admin_set_dating_hour_min_participants,age_compatible,age_compatible_bidirectional,answer_spice_question,assert_age_compatible,block_user,check_email_ban_status,consume_rate_limit,cool_match,create_match_if_mutual,end_match,find_user_by_code,get_current_or_next_dating_hour,get_dating_hour_min_participants,get_dating_hour_participant_count,get_find_match_candidates,get_last_dating_hour_preferences,get_match_partner_profile,get_match_quiz_state,get_meet_intent,get_my_active_dating_hour_session,get_my_active_random_chat,get_my_photo_appeal,get_nearby_profiles,get_public_profile,get_public_profiles,get_random_chat_session,get_spice_questions,get_user_mood,hide_match,is_current_user_admin,is_email_banned,join_dating_hour,join_random_chat,leave_dating_hour,leave_random_chat,like_user,list_blocked_users,list_my_likes_pending,list_my_matches_with_state,list_my_reports,list_my_soft_pings,list_received_likes_pending,match_bucket_add,match_bucket_delete,match_bucket_items,match_bucket_toggle,match_proximity_spark,profile_age,profile_discovery_visible,profile_discovery_visible_full,profile_distance_km,profile_to_jsonb,record_dating_hour_decision,register_chat_image_hash,relay_ack,relay_fetch,relay_store,respark_match,respond_to_like,save_dating_hour_preferences,send_soft_ping,session_meets_auth_requirements,set_match_kind,set_meet_intent,set_user_mood,start_quiz_attempt,submit_photo_appeal,submit_quiz_answer,submit_report,transit_presence_heartbeat,transit_presence_leave,unblock_user
$names$, ',');

  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND NOT (p.proname::text = ANY (v_ok))
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
  END LOOP;
END;
$sweep$;

-- -----------------------------------------------------------------------------
-- 3) Die Antwortschluessel-Helfer sind auch fuer `authenticated` zu - auch
--    dann, wenn sie (als spaetere Ueberladung) in die Allowlist geraten.
-- -----------------------------------------------------------------------------
DO $helpers$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname::text = ANY (string_to_array($names$
quiz_shuffle_for_match,quiz_pick_personalized,quiz_personal_distractors,quiz_stopwords,quiz_interest_catalog,_habitude_rank
$names$, ','))
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
  END LOOP;
END;
$helpers$;

-- -----------------------------------------------------------------------------
-- 4) BEWEIS - die Klassifikation prueft die Datenbank selbst, nicht dieser
--    Kommentar. Ein Fehler nennt immer die konkreten Functionen.
-- -----------------------------------------------------------------------------
DO $proof$
DECLARE
  v_bad text;
  v_cnt int;
  v_ok  text[];
BEGIN
  v_ok := string_to_array($names$
accept_soft_ping,acknowledge_photo_appeal,admin_decide_photo_appeal,admin_get_dating_hour_min_participants,admin_list_auto_verifications,admin_list_banned_emails,admin_list_bug_reports,admin_list_pending_verifications,admin_list_photo_appeals,admin_list_user_reports,admin_resolve_user_report,admin_set_dating_hour_min_participants,age_compatible,age_compatible_bidirectional,answer_spice_question,assert_age_compatible,block_user,check_email_ban_status,consume_rate_limit,cool_match,create_match_if_mutual,end_match,find_user_by_code,get_current_or_next_dating_hour,get_dating_hour_min_participants,get_dating_hour_participant_count,get_find_match_candidates,get_last_dating_hour_preferences,get_match_partner_profile,get_match_quiz_state,get_meet_intent,get_my_active_dating_hour_session,get_my_active_random_chat,get_my_photo_appeal,get_nearby_profiles,get_public_profile,get_public_profiles,get_random_chat_session,get_spice_questions,get_user_mood,hide_match,is_current_user_admin,is_email_banned,join_dating_hour,join_random_chat,leave_dating_hour,leave_random_chat,like_user,list_blocked_users,list_my_likes_pending,list_my_matches_with_state,list_my_reports,list_my_soft_pings,list_received_likes_pending,match_bucket_add,match_bucket_delete,match_bucket_items,match_bucket_toggle,match_proximity_spark,profile_age,profile_discovery_visible,profile_discovery_visible_full,profile_distance_km,profile_to_jsonb,record_dating_hour_decision,register_chat_image_hash,relay_ack,relay_fetch,relay_store,respark_match,respond_to_like,save_dating_hour_preferences,send_soft_ping,session_meets_auth_requirements,set_match_kind,set_meet_intent,set_user_mood,start_quiz_attempt,submit_photo_appeal,submit_quiz_answer,submit_report,transit_presence_heartbeat,transit_presence_leave,unblock_user
$names$, ',');

  -- (a) `anon` darf KEINE Function im Schema public aufrufen.
  SELECT count(*), string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.proname)
    INTO v_cnt, v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND has_function_privilege('anon', p.oid, 'EXECUTE');

  IF v_cnt > 0 THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: % public Functions sind fuer anon aufrufbar: %',
      v_cnt, v_bad;
  END IF;

  -- (b) KEINE App-RPC und KEINE Policy-/View-Function darf `authenticated`
  --     verloren haben - sonst waere die App nach diesem Push kaputt.
  SELECT count(*), string_agg(DISTINCT p.proname::text, ', ' ORDER BY p.proname::text)
    INTO v_cnt, v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname::text = ANY (v_ok)
     AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE');

  IF v_cnt > 0 THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: % Allowlist-Functions fehlen fuer authenticated: %',
      v_cnt, v_bad;
  END IF;

  -- (c) Die internen Antwortschluessel-Helfer sind auch fuer `authenticated` zu.
  SELECT count(*), string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.proname)
    INTO v_cnt, v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname::text = ANY (string_to_array($names$
quiz_shuffle_for_match,quiz_pick_personalized,quiz_personal_distractors,quiz_stopwords,quiz_interest_catalog,_habitude_rank
$names$, ','))
     AND has_function_privilege('authenticated', p.oid, 'EXECUTE');

  IF v_cnt > 0 THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: % interne Helfer sind fuer authenticated aufrufbar: %',
      v_cnt, v_bad;
  END IF;
END;
$proof$;
