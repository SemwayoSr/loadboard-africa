-- Launch review helper: an admin can approve a company after reviewing the AI result and authentication checks.
-- This deliberately does not auto-verify businesses or claim cargo/fuel ownership.
CREATE OR REPLACE FUNCTION public.admin_verify_company(target_company_id uuid, note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
  UPDATE public.companies
  SET verification_status = 'verified', verified_at = now(), verification_notes = note
  WHERE id = target_company_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_verify_company(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_verify_company(uuid,text) TO authenticated;
