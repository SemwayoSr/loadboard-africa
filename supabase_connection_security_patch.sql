-- Optional hardening patch for connection requests
-- Prevent a user from claiming an arbitrary shipper when requesting a load.

drop policy if exists "Transporters can request connections" on public.connection_requests;
create policy "Transporters can request connections"
on public.connection_requests
for insert
to authenticated
with check (
  transporter_id = auth.uid()
  and exists (
    select 1 from public.loads l
    where l.id = load_id
      and l.posted_by = shipper_id
      and l.status <> 'cancelled'
  )
);
