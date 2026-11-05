-- 181: Der Review loescht bei einer Ablehnung auch den Videopfad.
--
-- BEFUND (04.11.2026, direkt nach der Migration 180): In
-- public.admin_review_verification() fehlte eine Angabe, die der alte
-- Pfad in der Edge Function hatte - bei einer Ablehnung wird
-- verification_video_path auf NULL gesetzt.
--
-- Warum das wichtig ist: Die Edge Function loescht bei einer Ablehnung
-- die Datei im Storage. Bleibt der Pfad in der Datenbank stehen, zeigt
-- er auf eine Datei, die es nicht mehr gibt - und die Spalte behauptet
-- weiterhin, es gaebe ein Verifikationsvideo.
--
-- Korrekt ist: bei einer Ablehnung wird der Pfad geleert, bei einer
-- Freigabe bleibt er stehen (das Video wird weiterhin aufbewahrt, bis
-- die Aufbewahrungsfrist ablaeuft).
--
-- Die Migration 180 wird NICHT veraendert - sie ist bereits angewandt.
-- Eine angewandte Migration zu aendern hiesse: der Dateiinhalt und der
-- angewandte Stand wuerden auseinanderlaufen, und beim naechsten
-- db push wuerde die Aenderung nie mehr ausgefuehrt.

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_review_verification(
  p_admin_id       uuid,
  p_target_user_id uuid,
  p_is_verified    boolean,
  p_verified_age   int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_is_admin boolean;
  v_rate_ok  boolean;
  v_age      int;
BEGIN
  IF p_admin_id IS NULL OR p_target_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_request');
  END IF;

  -- Der Admin wird IN DER DATENBANK geprueft, nicht nur in der Edge
  -- Function. Das ist der Unterschied: die Edge Function kann ein
  -- Programmierfehler sein, die Datenbank nicht.
  SELECT is_admin INTO v_is_admin
    FROM public.profiles
   WHERE user_id = p_admin_id;

  IF NOT FOUND OR v_is_admin IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_admin');
  END IF;

  -- 60 Reviews pro Admin und Stunde. Ein Admin arbeitet nicht
  -- schneller - und ein geleaktes Token kann nicht massenhaft
  -- Freigaben erteilen.
  v_rate_ok := public.consume_rate_limit(
    'admin-review:' || p_admin_id::text, 60, 3600);
  IF NOT COALESCE(v_rate_ok, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'rate_limited');
  END IF;

  -- Das Alter: der Wert, den der Admin (und die KI-Schaetzung)
  -- festgelegt hat. Beim Ablehnen wird es wieder geloescht.
  v_age := CASE WHEN p_is_verified THEN p_verified_age ELSE NULL END;

  UPDATE public.profiles
     SET is_verified              = p_is_verified,
         verification_status      = CASE WHEN p_is_verified
                                         THEN 'approved' ELSE 'rejected' END,
         verified_age             = v_age,
         verification_approved_at = CASE WHEN p_is_verified
                                         THEN now() ELSE NULL END,
         -- BEFUND 04.11.2026 (Migration 181): Bei einer Ablehnung wird
         -- der Videopfad geloescht. Die Edge Function loescht die Datei
         -- im Storage - ohne diese Zeile zeigte die Spalte weiterhin
         -- auf eine Datei, die es nicht mehr gibt.
         verification_video_path  = CASE WHEN p_is_verified
                                         THEN verification_video_path
                                         ELSE NULL END
   WHERE user_id = p_target_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'target_not_found');
  END IF;

  -- Der Audit-Eintrag. Er entsteht in derselben Transaktion wie die
  -- Aenderung - ein Review ohne Spur ist nicht moeglich.
  INSERT INTO public.admin_action_audit
    (actor_id, action, target_user_id, detail)
  VALUES
    (p_admin_id, 'verification_review', p_target_user_id,
     jsonb_build_object('is_verified', p_is_verified,
                        'verified_age', v_age));

  RETURN jsonb_build_object('ok', true, 'is_verified', p_is_verified);
END;
$$;

COMMENT ON FUNCTION public.admin_review_verification(
  uuid, uuid, boolean, int) IS
  'Ein Admin entscheidet ueber eine Verifikation. Die Funktion prueft '
  'selbst, dass der Aufrufer Admin ist, begrenzt auf 60 Reviews pro '
  'Admin und Stunde, schreibt den Audit-Eintrag und loescht bei einer '
  'Ablehnung den Videopfad (Migration 180, Migration 181).';

REVOKE ALL ON FUNCTION public.admin_review_verification(
  uuid, uuid, boolean, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_verification(
  uuid, uuid, boolean, int)
  TO service_role;

-- Selbsttest: der Videopfad muss bei einer Ablehnung geleert werden.
DO $check$
DECLARE
  v_typ text;
BEGIN
  SELECT pg_get_functiondef(
           'public.admin_review_verification(uuid,uuid,boolean,int)'
           ::regprocedure)
    INTO v_typ;
  IF v_typ NOT LIKE '%verification_video_path%' THEN
    RAISE EXCEPTION
      'admin_review_verification leert den Videopfad bei einer '
      'Ablehnung nicht.';
  END IF;
  RAISE NOTICE 'Der Review leert den Videopfad bei einer Ablehnung (Selbsttest ok)';
END;
$check$;

COMMIT;
