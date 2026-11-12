-- Adjuntos del chat (RF-16, semana 5): fotos y PDF que se comparten en una
-- conversación entre dueño y clínica.
-- Bucket privado SIN políticas para la app: solo se sube y se lee con
-- enlaces firmados que entrega la Edge Function adjuntos-chat después de
-- verificar en Firestore que quien pide es participante activo del chat
-- (Supabase no puede consultar Firestore en sus políticas). Sin políticas
-- en storage.objects para este bucket, la app no puede listar, leer ni
-- escribir directamente.
--
-- Ruta: {chatId}/{uuid}-{nombre}. JPG, PNG o PDF de máximo 10 MB (el bucket
-- rechaza lo demás aunque el enlace firmado sea válido).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chats', 'chats', false, 10485760,
        array['image/jpeg', 'image/png', 'application/pdf'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
