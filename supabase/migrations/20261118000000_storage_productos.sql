-- Fotos de productos de la tienda (RF-07, semana 6). Bucket propio para los
-- límites exactos: JPG/PNG de máximo 1 MB (la app comprime antes de subir;
-- RF-07 rechaza archivos de más de 5 MB antes de comprimir).
--
-- Ruta: {uidDeLaClínica}/{productId}.jpg|png  (= products/{id}.fotoPath)
-- - Escribe: solo la cuenta de la clínica, en su propia carpeta
--   (firestore.rules exige la misma carpeta en fotoPath).
-- - Lee: cualquier usuario con sesión (enlaces firmados; bucket privado).
-- Usa public.es_token_mascoti() de 20261015000000_storage_mascotas.sql.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('productos', 'productos', false, 1048576, array['image/jpeg', 'image/png'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- true si la ruta es {uid del token}/{productId}.jpg|png.
create or replace function public.es_foto_producto_propia(ruta text)
returns boolean
language sql
stable
as $$
  select public.es_token_mascoti()
     and (storage.foldername(ruta))[1] = (auth.jwt() ->> 'sub')
     and ruta ~ '^[^/]+/[A-Za-z0-9_-]+\.(jpg|png)$';
$$;

drop policy if exists "productos: leer con sesión" on storage.objects;
create policy "productos: leer con sesión"
  on storage.objects for select to authenticated
  using (bucket_id = 'productos' and public.es_token_mascoti());

drop policy if exists "productos: la clínica sube" on storage.objects;
create policy "productos: la clínica sube"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'productos' and public.es_foto_producto_propia(name));

drop policy if exists "productos: la clínica reemplaza" on storage.objects;
create policy "productos: la clínica reemplaza"
  on storage.objects for update to authenticated
  using (bucket_id = 'productos' and public.es_foto_producto_propia(name))
  with check (bucket_id = 'productos' and public.es_foto_producto_propia(name));

drop policy if exists "productos: la clínica borra" on storage.objects;
create policy "productos: la clínica borra"
  on storage.objects for delete to authenticated
  using (bucket_id = 'productos' and public.es_foto_producto_propia(name));
