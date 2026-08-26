-- LoadBoard Africa V4: multi-role company structure + verification + fuel marketplace
-- Safe migration: preserves existing tables/data and keeps profiles.role for backward compatibility.

DO $$ BEGIN
  CREATE TYPE public.business_role AS ENUM ('shipper','freight_broker','transporter','fuel_supplier','fuel_buyer');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.verification_status AS ENUM ('not_started','pending','verified','needs_review','rejected');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('company_registration','representative_id','mandate','other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Company-level roles. A company can have many roles.
CREATE TABLE IF NOT EXISTS public.company_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  role public.business_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, role)
);

CREATE INDEX IF NOT EXISTS company_roles_company_idx ON public.company_roles(company_id);
CREATE INDEX IF NOT EXISTS company_roles_role_idx ON public.company_roles(role);

-- Company verification state. One simple launch-level verification.
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS verification_status public.verification_status NOT NULL DEFAULT 'not_started';
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS verification_notes text;
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS representative_name text;
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS representative_phone text;
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS verified_at timestamptz;

-- Verification documents. Store only secure storage paths, never public document URLs.
CREATE TABLE IF NOT EXISTS public.verification_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  document_type public.document_type NOT NULL,
  storage_path text NOT NULL,
  original_filename text,
  mime_type text,
  analysis_status text NOT NULL DEFAULT 'pending',
  ai_result jsonb,
  uploaded_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS verification_documents_company_idx ON public.verification_documents(company_id);

-- Broker mandates / Letters of Authority.
CREATE TABLE IF NOT EXISTS public.broker_mandates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  broker_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_name text NOT NULL,
  cargo_owner text,
  commodity text,
  origin text,
  destination text,
  quantity numeric,
  quantity_unit text,
  mandate_date date,
  valid_until date,
  authorised_representative text,
  signature_present boolean DEFAULT false,
  storage_path text NOT NULL,
  status text NOT NULL DEFAULT 'submitted',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS broker_mandates_company_idx ON public.broker_mandates(company_id);

-- Keep the existing loads table and add fields required for broker/client attribution.
ALTER TABLE public.loads ADD COLUMN IF NOT EXISTS poster_business_role public.business_role;
ALTER TABLE public.loads ADD COLUMN IF NOT EXISTS posting_for text NOT NULL DEFAULT 'own_account';
ALTER TABLE public.loads ADD COLUMN IF NOT EXISTS client_name text;
ALTER TABLE public.loads ADD COLUMN IF NOT EXISTS mandate_id uuid REFERENCES public.broker_mandates(id) ON DELETE SET NULL;
ALTER TABLE public.loads ADD COLUMN IF NOT EXISTS offer_enabled boolean NOT NULL DEFAULT false;

-- Fuel listing enhancements. Keep existing columns intact.
ALTER TABLE public.fuel_listings ADD COLUMN IF NOT EXISTS grade_specification text;
ALTER TABLE public.fuel_listings ADD COLUMN IF NOT EXISTS minimum_order numeric;
ALTER TABLE public.fuel_listings ADD COLUMN IF NOT EXISTS delivery_options text;
ALTER TABLE public.fuel_listings ADD COLUMN IF NOT EXISTS incoterms text;
ALTER TABLE public.fuel_listings ADD COLUMN IF NOT EXISTS additional_notes text;
ALTER TABLE public.fuel_listings ADD COLUMN IF NOT EXISTS unit text;

-- Buyer requirements.
CREATE TABLE IF NOT EXISTS public.fuel_requirements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  product text NOT NULL,
  grade_specification text,
  required_quantity numeric,
  unit text DEFAULT 'litres',
  target_location text,
  delivery_location text,
  required_date date,
  frequency text,
  contract_duration text,
  payment_terms text,
  additional_requirements text,
  status text NOT NULL DEFAULT 'open',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS fuel_requirements_status_idx ON public.fuel_requirements(status);
CREATE INDEX IF NOT EXISTS fuel_requirements_buyer_idx ON public.fuel_requirements(buyer_id);

-- Fuel enquiries and offers, separate from cargo connections.
CREATE TABLE IF NOT EXISTS public.fuel_enquiries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid REFERENCES public.fuel_listings(id) ON DELETE CASCADE,
  requirement_id uuid REFERENCES public.fuel_requirements(id) ON DELETE CASCADE,
  buyer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  supplier_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  message text,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (listing_id IS NOT NULL OR requirement_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS public.fuel_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enquiry_id uuid REFERENCES public.fuel_enquiries(id) ON DELETE CASCADE,
  supplier_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  buyer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  price numeric,
  currency text DEFAULT 'USD',
  quantity numeric,
  unit text DEFAULT 'litres',
  payment_terms text,
  delivery_terms text,
  valid_until date,
  message text,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Basic shared messaging foundation.
CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject text,
  body text NOT NULL,
  load_id uuid REFERENCES public.loads(id) ON DELETE SET NULL,
  connection_id uuid REFERENCES public.connection_requests(id) ON DELETE SET NULL,
  fuel_enquiry_id uuid REFERENCES public.fuel_enquiries(id) ON DELETE SET NULL,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS messages_recipient_idx ON public.messages(recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS messages_sender_idx ON public.messages(sender_id, created_at DESC);

-- Storage bucket for private business/mandate/verification documents.
INSERT INTO storage.buckets (id, name, public)
VALUES ('business-documents', 'business-documents', false)
ON CONFLICT (id) DO NOTHING;

-- RLS
ALTER TABLE public.company_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.broker_mandates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fuel_requirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fuel_enquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fuel_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Company roles: users can see roles for companies they belong to; company members can manage their roles.
DROP POLICY IF EXISTS "Authenticated users can view company roles" ON public.company_roles;
CREATE POLICY "Authenticated users can view company roles" ON public.company_roles
FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Company members can add roles" ON public.company_roles;
CREATE POLICY "Company members can add roles" ON public.company_roles
FOR INSERT TO authenticated
WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.company_id = company_roles.company_id));

DROP POLICY IF EXISTS "Company members can remove roles" ON public.company_roles;
CREATE POLICY "Company members can remove roles" ON public.company_roles
FOR DELETE TO authenticated
USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.company_id = company_roles.company_id));

-- Verification docs: company members can create/view their own company's documents.
DROP POLICY IF EXISTS "Company members can view verification documents" ON public.verification_documents;
CREATE POLICY "Company members can view verification documents" ON public.verification_documents
FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.company_id = verification_documents.company_id));

DROP POLICY IF EXISTS "Company members can upload verification documents" ON public.verification_documents;
CREATE POLICY "Company members can upload verification documents" ON public.verification_documents
FOR INSERT TO authenticated
WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.company_id = verification_documents.company_id));

-- Mandates are private to the broker company.
DROP POLICY IF EXISTS "Broker company can view mandates" ON public.broker_mandates;
CREATE POLICY "Broker company can view mandates" ON public.broker_mandates
FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.company_id = broker_mandates.company_id));

DROP POLICY IF EXISTS "Broker company can submit mandates" ON public.broker_mandates;
CREATE POLICY "Broker company can submit mandates" ON public.broker_mandates
FOR INSERT TO authenticated
WITH CHECK (broker_id = auth.uid() AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.company_id = broker_mandates.company_id));

-- Fuel requirements.
DROP POLICY IF EXISTS "Authenticated users can view open fuel requirements" ON public.fuel_requirements;
CREATE POLICY "Authenticated users can view open fuel requirements" ON public.fuel_requirements
FOR SELECT TO authenticated USING (status = 'open' OR buyer_id = auth.uid());

DROP POLICY IF EXISTS "Fuel buyers can post requirements" ON public.fuel_requirements;
CREATE POLICY "Fuel buyers can post requirements" ON public.fuel_requirements
FOR INSERT TO authenticated WITH CHECK (buyer_id = auth.uid());

DROP POLICY IF EXISTS "Fuel buyers can update requirements" ON public.fuel_requirements;
CREATE POLICY "Fuel buyers can update requirements" ON public.fuel_requirements
FOR UPDATE TO authenticated USING (buyer_id = auth.uid()) WITH CHECK (buyer_id = auth.uid());

-- Fuel enquiries.
DROP POLICY IF EXISTS "Fuel participants can view enquiries" ON public.fuel_enquiries;
CREATE POLICY "Fuel participants can view enquiries" ON public.fuel_enquiries
FOR SELECT TO authenticated USING (buyer_id = auth.uid() OR supplier_id = auth.uid());

DROP POLICY IF EXISTS "Authenticated users can create fuel enquiries" ON public.fuel_enquiries;
CREATE POLICY "Authenticated users can create fuel enquiries" ON public.fuel_enquiries
FOR INSERT TO authenticated WITH CHECK (buyer_id = auth.uid() OR supplier_id = auth.uid());

DROP POLICY IF EXISTS "Fuel participants can update enquiries" ON public.fuel_enquiries;
CREATE POLICY "Fuel participants can update enquiries" ON public.fuel_enquiries
FOR UPDATE TO authenticated USING (buyer_id = auth.uid() OR supplier_id = auth.uid()) WITH CHECK (buyer_id = auth.uid() OR supplier_id = auth.uid());

-- Fuel offers.
DROP POLICY IF EXISTS "Fuel participants can view offers" ON public.fuel_offers;
CREATE POLICY "Fuel participants can view offers" ON public.fuel_offers
FOR SELECT TO authenticated USING (buyer_id = auth.uid() OR supplier_id = auth.uid());

DROP POLICY IF EXISTS "Suppliers can create fuel offers" ON public.fuel_offers;
CREATE POLICY "Suppliers can create fuel offers" ON public.fuel_offers
FOR INSERT TO authenticated WITH CHECK (supplier_id = auth.uid());

-- Messages: only sender/recipient.
DROP POLICY IF EXISTS "Users can view their messages" ON public.messages;
CREATE POLICY "Users can view their messages" ON public.messages
FOR SELECT TO authenticated USING (sender_id = auth.uid() OR recipient_id = auth.uid());

DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
CREATE POLICY "Users can send messages" ON public.messages
FOR INSERT TO authenticated WITH CHECK (sender_id = auth.uid());

DROP POLICY IF EXISTS "Recipients can mark messages read" ON public.messages;
CREATE POLICY "Recipients can mark messages read" ON public.messages
FOR UPDATE TO authenticated USING (recipient_id = auth.uid()) WITH CHECK (recipient_id = auth.uid());

-- Storage policies for private business documents.
DROP POLICY IF EXISTS "Company members can upload business documents" ON storage.objects;
CREATE POLICY "Company members can upload business documents" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'business-documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users can view own business documents" ON storage.objects;
CREATE POLICY "Users can view own business documents" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'business-documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Safe backfill from the old single role where a company already exists.
INSERT INTO public.company_roles(company_id, role)
SELECT DISTINCT p.company_id,
  CASE p.role::text
    WHEN 'shipper' THEN 'shipper'::public.business_role
    WHEN 'transporter' THEN 'transporter'::public.business_role
    WHEN 'supplier' THEN 'fuel_supplier'::public.business_role
    ELSE NULL
  END
FROM public.profiles p
WHERE p.company_id IS NOT NULL
  AND p.role::text IN ('shipper','transporter','supplier')
ON CONFLICT (company_id, role) DO NOTHING;

-- Preserve existing users and loads. No deletes or destructive migration are performed.
