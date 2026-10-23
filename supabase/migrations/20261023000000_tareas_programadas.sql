-- Tareas programadas (semana 4). Reemplazan a las funciones programadas de
-- Firebase (necesitan el plan Blaze): pg_cron llama a la Edge Function
-- tareas-programadas con pg_net.
--
-- Antes de aplicar, guarda el mismo valor del secreto CRON_SECRET de las
-- Edge Functions en el Vault (una sola vez, en SQL Editor):
--   select vault.create_secret('<el mismo valor de CRON_SECRET>', 'cron_secret');
--
-- Se puede ejecutar varias veces: cron.schedule reemplaza el trabajo que
-- tenga el mismo nombre.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Llama a tareas-programadas con {tarea} y el secreto en el encabezado.
create or replace function public.ejecutar_tarea_programada(p_tarea text)
returns bigint
language sql
security definer
set search_path = public
as $$
  select net.http_post(
    url := 'https://tahnazumbqsupzpusrba.supabase.co/functions/v1/tareas-programadas',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := jsonb_build_object('tarea', p_tarea),
    timeout_milliseconds := 60000
  );
$$;

revoke all on function public.ejecutar_tarea_programada(text) from public, anon, authenticated;

-- RF-14: cada 30 min, citas no asistidas y solicitudes expiradas.
select cron.schedule('citas-vencidas', '*/30 * * * *', $$select public.ejecutar_tarea_programada('vencidas')$$);

-- RF-13: recordatorios diarios a las 8:00 a. m. hora Colombia = 13:00 UTC
-- (Colombia no tiene horario de verano).
select cron.schedule('recordatorios-diarios', '0 13 * * *', $$select public.ejecutar_tarea_programada('recordatorios')$$);
