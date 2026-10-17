// Solo para Deno (Edge Functions). Enlaces firmados del Storage de Supabase
// con la service_role key (la que el entorno de las Edge Functions trae).
function credenciales(): { url: string; llave: string } {
  const url = Deno.env.get("SUPABASE_URL");
  const llave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !llave) throw new Error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY");
  return { url, llave };
}

const ruta = (path: string) => path.split("/").map(encodeURIComponent).join("/");

/** Enlace de subida de un solo uso (la app usa uploadBinaryToSignedUrl). */
export async function firmarSubida(bucket: string, path: string): Promise<{ token: string }> {
  const { url, llave } = credenciales();
  const respuesta = await fetch(`${url}/storage/v1/object/upload/sign/${bucket}/${ruta(path)}`, {
    method: "POST",
    headers: { "apikey": llave, "Authorization": `Bearer ${llave}` },
  });
  if (!respuesta.ok) throw new Error(`Storage ${respuesta.status}: ${await respuesta.text()}`);
  const { url: firmada } = await respuesta.json() as { url: string };
  const token = new URL(firmada, url).searchParams.get("token");
  if (!token) throw new Error("Storage no devolvió el token de subida");
  return { token };
}

/** Enlace de lectura temporal. */
export async function firmarLectura(bucket: string, path: string, segundos: number): Promise<string> {
  const { url, llave } = credenciales();
  const respuesta = await fetch(`${url}/storage/v1/object/sign/${bucket}/${ruta(path)}`, {
    method: "POST",
    headers: { "apikey": llave, "Authorization": `Bearer ${llave}`, "Content-Type": "application/json" },
    body: JSON.stringify({ expiresIn: segundos }),
  });
  if (!respuesta.ok) throw new Error(`Storage ${respuesta.status}: ${await respuesta.text()}`);
  const { signedURL } = await respuesta.json() as { signedURL: string };
  return `${url}/storage/v1${signedURL}`;
}
