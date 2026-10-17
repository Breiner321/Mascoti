-- Límite de intentos de la Edge Function vincular-mascota (semana 3): como
-- máximo N búsquedas de código por clínica en una ventana de tiempo, para que
-- no se puedan adivinar códigos de paciente.
--
-- Solo lo usa la Edge Function con la service_role key: la tabla tiene RLS
-- activado y ninguna política, y la función no se expone a anon/authenticated.

create table if not exists public.intentos_vinculacion (
  id bigint generated always as identity primary key,
  clinic_id text not null,
  intentado_en timestamptz not null default now()
);

create index if not exists intentos_vinculacion_clinica_fecha
  on public.intentos_vinculacion (clinic_id, intentado_en);

alter table public.intentos_vinculacion enable row level security;

-- Registra un intento si la clínica no superó el límite y dice si se permite.
-- Atómico: un candado por clínica evita que dos peticiones simultáneas pasen
-- el límite.
create or replace function public.registrar_intento_vinculacion(
  p_clinic_id text,
  p_maximo integer default 10,
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
  perform pg_advisory_xact_lock(hashtext('vinculacion:' || p_clinic_id));

  -- Limpieza: los intentos fuera de la ventana ya no cuentan.
  delete from public.intentos_vinculacion
   where clinic_id = p_clinic_id and intentado_en < v_desde;

  select count(*), min(intentado_en)
    into v_intentos, v_primero
    from public.intentos_vinculacion
   where clinic_id = p_clinic_id;

  if v_intentos >= p_maximo then
    return query select
      false,
      greatest(1, ceil(extract(epoch from (v_primero + make_interval(mins => p_ventana_minutos) - now())))::integer);
    return;
  end if;

  insert into public.intentos_vinculacion (clinic_id) values (p_clinic_id);
  return query select true, 0;
end;
$$;

revoke all on function public.registrar_intento_vinculacion(text, integer, integer) from public, anon, authenticated;
grant execute on function public.registrar_intento_vinculacion(text, integer, integer) to service_role;
