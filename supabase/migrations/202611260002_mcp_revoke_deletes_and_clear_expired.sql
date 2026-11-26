-- Revoking an MCP grant now deletes the grant record immediately instead of
-- leaving zombie "revoked" cards in the user's connection list. Historical
-- audit logs remain intact via grant_id ON DELETE SET NULL + grant_label.
-- Also adds clear_expired_national_focus_mcp_grants() for one-click cleanup
-- of naturally expired grants.

delete from public.national_focus_mcp_grants
where revoked_at is not null;

create or replace function public.revoke_national_focus_mcp_grant(p_grant_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;

  delete from public.national_focus_mcp_grants
  where id = p_grant_id and user_id = auth.uid();

  if not found then
    raise exception 'grant unavailable' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.revoke_all_national_focus_mcp_grants()
returns integer
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  revoked_count integer;
begin
  if auth.uid() is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;

  delete from public.national_focus_mcp_grants
  where user_id = auth.uid()
    and revoked_at is null
    and (expires_at is null or expires_at > now());

  get diagnostics revoked_count = row_count;
  return revoked_count;
end;
$$;

create or replace function public.clear_expired_national_focus_mcp_grants()
returns integer
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  deleted_count integer;
begin
  if auth.uid() is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;

  delete from public.national_focus_mcp_grants
  where user_id = auth.uid()
    and (revoked_at is not null or (expires_at is not null and expires_at <= now()));

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function
  public.revoke_national_focus_mcp_grant(uuid),
  public.revoke_all_national_focus_mcp_grants(),
  public.clear_expired_national_focus_mcp_grants()
  from public, anon;

grant execute on function
  public.revoke_national_focus_mcp_grant(uuid),
  public.revoke_all_national_focus_mcp_grants(),
  public.clear_expired_national_focus_mcp_grants()
  to authenticated;
