-- Allow authenticated users to permanently delete their own revoked or expired
-- MCP grant records while keeping historical audit logs (grant_id ON DELETE SET NULL).

create or replace function public.delete_national_focus_mcp_grant(p_grant_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  g public.national_focus_mcp_grants;
begin
  if auth.uid() is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;

  select * into g
  from public.national_focus_mcp_grants
  where id = p_grant_id and user_id = auth.uid();

  if not found then
    raise exception 'grant unavailable' using errcode = '42501';
  end if;

  if g.revoked_at is null and (g.expires_at is null or g.expires_at > now()) then
    raise exception 'active grant cannot be deleted' using errcode = '22023';
  end if;

  delete from public.national_focus_mcp_grants
  where id = p_grant_id and user_id = auth.uid();
end;
$$;

revoke all on function public.delete_national_focus_mcp_grant(uuid)
  from public, anon;

grant execute on function public.delete_national_focus_mcp_grant(uuid)
  to authenticated;
