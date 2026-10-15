-- Storage de Mascoti (Supabase). Reemplaza a Firebase Storage + storage.rules.
--
-- Los usuarios inician sesión con Firebase; Supabase acepta sus ID tokens
-- (Third-party Auth → Firebase mascoti-b27cf). Por eso el uid es el `sub`
-- del token: se usa auth.jwt() ->> 'sub' (NO auth.uid(), que espera un uuid).
--
-- Estructura: usuarios/{uidFirebase}/... Cada usuario solo lee y escribe su
-- carpeta. Los archivos que debe ver otra persona (chat, historial médico)
-- se comparten con enlaces firmados temporales (StorageRepository.signedUrl
-- desde quien tiene acceso, o una Edge Function cuando haga falta validar).

-- Bucket privado, máximo 10 MB por archivo, solo imágenes y PDF.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'mascoti',
  'mascoti',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- true si la ruta del objeto está en la carpeta del usuario del token.
create or replace function public.es_carpeta_propia(ruta text)
returns boolean
language sql
stable
as $$
  select (storage.foldername(ruta))[1] = 'usuarios'
     and (storage.foldername(ruta))[2] = (auth.jwt() ->> 'sub')
     and (auth.jwt() ->> 'iss') = 'https://securetoken.google.com/mascoti-b27cf';
$$;

drop policy if exists "mascoti: leer lo propio" on storage.objects;
create policy "mascoti: leer lo propio"
  on storage.objects for select to authenticated
  using (bucket_id = 'mascoti' and public.es_carpeta_propia(name));

drop policy if exists "mascoti: subir a lo propio" on storage.objects;
create policy "mascoti: subir a lo propio"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'mascoti' and public.es_carpeta_propia(name));

drop policy if exists "mascoti: reemplazar lo propio" on storage.objects;
create policy "mascoti: reemplazar lo propio"
  on storage.objects for update to authenticated
  using (bucket_id = 'mascoti' and public.es_carpeta_propia(name))
  with check (bucket_id = 'mascoti' and public.es_carpeta_propia(name));

drop policy if exists "mascoti: borrar lo propio" on storage.objects;
create policy "mascoti: borrar lo propio"
  on storage.objects for delete to authenticated
  using (bucket_id = 'mascoti' and public.es_carpeta_propia(name));
