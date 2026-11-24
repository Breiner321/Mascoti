-- Documentos PDF generados por Mascoti (RF-18, semana 7): carnet de vacunas.
-- Bucket privado SIN políticas para la app: solo la Edge Function
-- generar-carnet sube el PDF (service_role) y entrega un enlace firmado de
-- 15 minutos después de verificar en Firestore que quien pide es el dueño.
--
-- Ruta: pets/{petId}/documentos/carnet-AAAA-MM-DD.pdf. Solo PDF, máximo 5 MB.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('documentos', 'documentos', false, 5242880, array['application/pdf'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
