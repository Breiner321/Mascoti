-- Fotos de mascotas (semana 2). Bucket propio para aplicar límites exactos:
-- solo JPG/PNG de máximo 5 MB (en Supabase el tamaño y el tipo se limitan
-- por bucket, no por ruta).
--
-- Ruta: {uidDelDueño}/{petId}/foto.jpg|png  (igual a pets/{petId}.fotoPath)
-- - Escribe: solo el dueño, en su propia carpeta.
-- - Lee: cualquier usuario con sesión (las clínicas ven la foto en la agenda
--   y el historial). El bucket es privado: se lee con enlaces firmados.
-- El uid es el `sub` del token de Firebase (Third-party Auth): se usa
-- auth.jwt() ->> 'sub', no auth.uid() (que espera un uuid).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('mascotas', 'mascotas', false, 5242880, array['image/jpeg', 'image/png'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Token emitido por el proyecto de Firebase de Mascoti.
create or replace function public.es_token_mascoti()
returns boolean
language sql
stable
as $$
  select (auth.jwt() ->> 'iss') = 'https://securetoken.google.com/mascoti-b27cf';
$$;

-- true si la ruta es {uid del token}/{petId}/foto.jpg|png.
create or replace function public.es_foto_mascota_propia(ruta text)
returns boolean
language sql
stable
as $$
  select public.es_token_mascoti()
     and (storage.foldername(ruta))[1] = (auth.jwt() ->> 'sub')
     and ruta ~ '^[^/]+/[^/]+/foto\.(jpg|png)$';
$$;

drop policy if exists "mascotas: leer con sesión" on storage.objects;
create policy "mascotas: leer con sesión"
  on storage.objects for select to authenticated
  using (bucket_id = 'mascotas' and public.es_token_mascoti());

drop policy if exists "mascotas: el dueño sube" on storage.objects;
create policy "mascotas: el dueño sube"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'mascotas' and public.es_foto_mascota_propia(name));

drop policy if exists "mascotas: el dueño reemplaza" on storage.objects;
create policy "mascotas: el dueño reemplaza"
  on storage.objects for update to authenticated
  using (bucket_id = 'mascotas' and public.es_foto_mascota_propia(name))
  with check (bucket_id = 'mascotas' and public.es_foto_mascota_propia(name));

drop policy if exists "mascotas: el dueño borra" on storage.objects;
create policy "mascotas: el dueño borra"
  on storage.objects for delete to authenticated
  using (bucket_id = 'mascotas' and public.es_foto_mascota_propia(name));
