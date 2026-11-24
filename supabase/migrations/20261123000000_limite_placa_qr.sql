-- Límite de "Ver teléfono" en la página pública de la placa QR (RF-17,
-- semana 7): como máximo N revelaciones por IP en una ventana de tiempo,
-- para que nadie recorra placas sacando teléfonos.
--
-- No guarda la IP: guarda su SHA-256. Solo lo usa la Edge Function
-- placa-publica con la service_role key: RLS activado y sin políticas.

create table if not exists public.intentos_placa (
  id bigint generated always as identity primary key,
  ip_hash text not null,
  intentado_en timestamptz not null default now()
);

create index if not exists intentos_placa_ip_fecha
  on public.intentos_placa (ip_hash, intentado_en);

alter table public.intentos_placa enable row level security;

-- Registra un intento si la IP no superó el límite y dice si se permite.
-- Atómico: un candado por IP evita que dos peticiones pasen el límite.
create or replace function public.registrar_intento_placa(
  p_ip_hash text,
  p_maximo integer default 5,
  p_ventana_minutos integer default 60
)
returns table (permitido boolean, reintentar_en_segundos integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_desde timestamptz := now() - make_interval(mins => p_ventana_minutos);
  v_intentos integer;
  v_primero timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext('placa:' || p_ip_hash));

  delete from public.intentos_placa
   where ip_hash = p_ip_hash and intentado_en < v_desde;

  select count(*), min(intentado_en)
    into v_intentos, v_primero
    from public.intentos_placa
   where ip_hash = p_ip_hash;

  if v_intentos >= p_maximo then
    return query select
      false,
      greatest(1, ceil(extract(epoch from (v_primero + make_interval(mins => p_ventana_minutos) - now())))::integer);
    return;
  end if;

  insert into public.intentos_placa (ip_hash) values (p_ip_hash);
  return query select true, 0;
end;
$$;

revoke all on function public.registrar_intento_placa(text, integer, integer) from public, anon, authenticated;
grant execute on function public.registrar_intento_placa(text, integer, integer) to service_role;
