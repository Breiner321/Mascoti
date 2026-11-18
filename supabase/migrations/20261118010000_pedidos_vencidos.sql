-- RF-12 (semana 6): cada 10 min, los pedidos 'pendiente_pago' de más de
-- 15 min pasan a 'expirado' y liberan el stock reservado. Usa
-- public.ejecutar_tarea_programada de 20261023000000_tareas_programadas.sql
-- (secreto cron_secret en el Vault). Se puede ejecutar varias veces.
select cron.schedule('pedidos-vencidos', '*/10 * * * *', $$select public.ejecutar_tarea_programada('pedidos-vencidos')$$);
