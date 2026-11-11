-- Cambio 4: veterinarias de OpenStreetMap en el mapa (Edge Function
-- veterinarias-cercanas). Solo la usa la Edge Function con la service_role
-- key: RLS activado y sin políticas; la función no se expone a la app.
-- Se puede ejecutar varias veces.

-- Caché por cuadros de ~5 km (24 h): una sola consulta a Overpass por zona.
create table if not exists public.cache_veterinarias_osm (
  cuadro text primary key,
  datos jsonb not null default '[]'::jsonb,
  actualizado timestamptz not null default now()
);
alter table public.cache_veterinarias_osm enable row level security;

-- Límite de consultas a Overpass por usuario.
create table if not exists public.consultas_mapa (
  id bigint generated always as identity primary key,
  uid text not null,
  consultado_en timestamptz not null default now()
);
create index if not exists consultas_mapa_uid_fecha on public.consultas_mapa (uid, consultado_en);
alter table public.consultas_mapa enable row level security;

-- Registra una consulta si el usuario no superó el límite y dice si se permite.
-- Atómico: un candado por usuario evita que dos peticiones pasen el límite.
create or replace function public.registrar_consulta_mapa(
  p_uid text,
  p_maximo integer default 60,
  p_ventana_minutos integer default 60
)
returns table (permitido boolean, reintentar_en_segundos integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_desde timestamptz := now() - make_interval(mins => p_ventana_minutos);
  v_consultas integer;
  v_primera timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext('mapa:' || p_uid));

  delete from public.consultas_mapa where uid = p_uid and consultado_en < v_desde;

  select count(*), min(consultado_en) into v_consultas, v_primera
    from public.consultas_mapa where uid = p_uid;

  if v_consultas >= p_maximo then
    return query select
      false,
      greatest(1, ceil(extract(epoch from (v_primera + make_interval(mins => p_ventana_minutos) - now())))::integer);
    return;
  end if;

  insert into public.consultas_mapa (uid) values (p_uid);
  return query select true, 0;
end;
$$;

revoke all on function public.registrar_consulta_mapa(text, integer, integer) from public, anon, authenticated;
grant execute on function public.registrar_consulta_mapa(text, integer, integer) to service_role;
