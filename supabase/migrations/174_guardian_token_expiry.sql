-- 174: Token-Ablauf auch beim Widerruf der Elternfreigabe
--
-- BEFUND (04.11.2026, Audit der Edge Functions):
--
-- Drei der vier Portal-RPCs pruefen, ob der Token noch nicht
-- abgelaufen ist:
--
--   * confirm_guardian_consent   (Migration 165, Zeile 433)
--   * set_guardian_portal_settings (Migration 165, Zeile 590)
--   * guardian_portal_status     (Migration 166, Zeile 46)
--
-- Nur revoke_guardian_consent_by_token tat das nicht. Ein abgelaufenes
-- Token (14 Tage) konnte damit noch den Widerruf ausloesen.
--
-- Der Schaden ist gering - ein Widerruf beendet eine Freigabe, die
-- nach 14 Tagen ohnehin ausgelaufen waere. Aber es ist eine
-- Inkonsistenz: ein Token, das nichts mehr darf, kann hier noch etwas
-- ausloesen. Und in einem Jahr, wenn jemand die Ablaufzeit auf 30
-- Tage verlaengert, wird aus dem Kleinen ein echtes Loch.
--
-- DieMigration aendert nur die Bedingung. Der Widerruf selbst ist
-- unveraendert.

BEGIN;

CREATE OR REPLACE FUNCTION public.revoke_guardian_consent_by_token(
  p_token text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row record;
BEGIN
  IF p_token IS NULL OR length(p_token) < 16 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  -- BEFUND 04.11.2026: Die Ablaufpruefung fehlte hier (die anderen
  -- drei Portal-Funktionen haben sie seit Migration 165/166).
  SELECT * INTO v_row
    FROM public.guardian_consents
   WHERE token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
     AND status IN ('pending','active')
     AND token_expires_at > now()
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  UPDATE public.guardian_consents
     SET status     = 'revoked',
         revoked_at = now(),
         revoked_by = 'guardian',
         updated_at = now()
   WHERE id = v_row.id;

  UPDATE public.profiles
     SET supervised         = false,
         consent_state      = 'revoked',
         consent_revoked_at = now(),
         updated_at         = now()
   WHERE user_id = v_row.child_user_id;

  INSERT INTO public.guardian_consent_audit
    (consent_id, child_user_id, actor, action, detail)
  VALUES
    (v_row.id, v_row.child_user_id, 'guardian', 'revoked',
     jsonb_build_object('via', 'token'));

  RETURN jsonb_build_object('ok', true);
END;
$$;

COMMENT ON FUNCTION public.revoke_guardian_consent_by_token(text) IS
  'Der Elternteil widerruft die Freigabe ueber sein Token. Prueft auch '
  'die Ablaufzeit des Tokens - das fehlte hier (v0.10.0, Migration 174); '
  'die drei anderen Portal-Funktionen pruefen es seit Migration 165/166.';

-- Die Rechte bleiben unveraendert.
REVOKE ALL ON FUNCTION public.revoke_guardian_consent_by_token(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_guardian_consent_by_token(text)
  TO service_role;

COMMIT;
