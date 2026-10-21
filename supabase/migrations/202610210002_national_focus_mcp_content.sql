-- Same independent delegate and same manually uploaded snapshot as T1.
-- No client role can call this service boundary; the public HTTP tools apply a
-- typed field whitelist before returning any content. Never select source logs.
create function public.read_national_focus_mcp_snapshot(
  p_token_hash text, p_expected_revision bigint default null
) returns jsonb language plpgsql stable security definer
set search_path = public, pg_catalog as $$
declare
  metadata jsonb;
  snapshot public.cloud_business_snapshots;
begin
  -- Both reads share this STABLE statement's MVCC snapshot. A concurrent manual
  -- upload cannot pair metadata from one revision with content from another.
  metadata := public.read_national_focus_mcp_metadata(p_token_hash, p_expected_revision);
  if p_expected_revision is not null and metadata ->> 'revision' is null then
    raise exception 'snapshot revision changed' using errcode = 'PT409';
  end if;
  if metadata ->> 'status' <> 'available' then
    return metadata;
  end if;
  select s.* into snapshot
  from public.cloud_business_snapshots s
  join public.national_focus_mcp_grants g on g.user_id = s.user_id
  where g.token_hash = p_token_hash;
  return metadata || jsonb_build_object('tables', jsonb_build_object(
    'local_national_focus_cards', snapshot.payload -> 'tables' -> 'local_national_focus_cards',
    'local_national_focus_strengthening_levels', snapshot.payload -> 'tables' -> 'local_national_focus_strengthening_levels',
    'local_national_focus_requirement_versions', snapshot.payload -> 'tables' -> 'local_national_focus_requirement_versions',
    'local_national_focus_maintenance', snapshot.payload -> 'tables' -> 'local_national_focus_maintenance'
  ));
end;
$$;
revoke all on function public.read_national_focus_mcp_snapshot(text, bigint)
  from public, anon, authenticated;
grant execute on function public.read_national_focus_mcp_snapshot(text, bigint)
  to service_role;
