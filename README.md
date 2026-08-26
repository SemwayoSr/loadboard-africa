# LoadBoard Africa V4

V4 updates the existing V3 platform without deleting the existing database tables or authentication flow.

## New structure
- Five business roles: Shipper, Freight Broker, Transporter/Carrier, Fuel Supplier, Fuel Buyer
- Multi-role company accounts using `company_roles`
- Role switcher in the header
- Company onboarding and add-role flow
- Business Verified foundation and private document storage
- Broker mandate / Letter of Authority upload for client loads
- Broker attribution on loads: own account vs client
- Separate Fuel Marketplace with supplier listings and buyer requirements
- Fuel enquiries and offers
- Shared messaging foundation
- Existing loads, connection requests and subscriptions remain in place

## Supabase migration
Run `migration_v4_multirole.sql` in Supabase SQL Editor after the existing V3 database and security patch.

## AI verification
The database stores `analysis_status` and `ai_result` for verification documents. The frontend queues documents as `pending` and does not falsely mark a business as verified. An AI service/Edge Function can later process the private documents and write the consistency result. A verified badge is only displayed when `companies.verification_status = 'verified'`.

## Security
The frontend uses only the Supabase public/anon key. Do not put a Supabase secret/service-role key into this file.
