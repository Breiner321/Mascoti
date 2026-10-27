-- Cambio 4 (ajuste): precarga de la caché de veterinarias de OpenStreetMap.
-- Los servidores públicos de Overpass a veces tardan más de 40 s, así que la
-- caché se llena en segundo plano y el mapa solo la lee.
--
-- Requiere la migración 20261023000000_tareas_programadas.sql (función
-- ejecutar_tarea_programada y el secreto cron_secret en el Vault) y
-- 20261028000000_veterinarias_osm.sql. Se puede ejecutar varias veces.

-- Cuadros que Overpass no pudo traer al abrir el mapa: la precarga los llena
-- primero. Un cuadro pendiente no se sirve como "sin veterinarias".
alter table public.cache_veterinarias_osm
  add column if not exists pendiente boolean not null default false;

create index if not exists cache_veterinarias_osm_renovar
  on public.cache_veterinarias_osm (actualizado);

-- Cada 2 horas (minuto 15): renueva lo vencido, lo pendiente y los
-- alrededores de las clínicas y las ciudades principales.
select cron.schedule(
  'precarga-veterinarias-osm',
  '15 */2 * * *',
  $$select public.ejecutar_tarea_programada('veterinarias-osm')$$
);
