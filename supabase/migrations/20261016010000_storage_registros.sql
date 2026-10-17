-- Adjuntos del historial médico (RF-08, semana 3): radiografías, exámenes…
-- Bucket privado SIN políticas para la app: solo se sube y se lee con
-- enlaces firmados que entrega la Edge Function adjuntos-historial después
-- de verificar en Firestore que quien pide es el dueño o una clínica
-- autorizada (Supabase no puede consultar Firestore en sus políticas).
--
-- Ruta: {petId}/{recordId}/{archivo}. JPG, PNG o PDF de máximo 10 MB.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('registros', 'registros', false, 10485760,
        array['image/jpeg', 'image/png', 'application/pdf'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
