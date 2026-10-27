// Solo para Deno (Edge Functions). Acceso al Postgres de Supabase con la
// service_role key por su API REST (PostgREST): caché y límites que no son
// datos de la app (los datos de la app siguen en Firestore).

function credenciales(): { url: string; llave: string } {
  const url = Deno.env.get("SUPABASE_URL");
  const llave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !llave) throw new Error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY");
  return { url, llave };
}

function encabezados(llave: string, extra: Record<string, string> = {}): Record<string, string> {
  return { "apikey": llave, "Authorization": `Bearer ${llave}`, "Content-Type": "application/json", ...extra };
}

/** Llama a una función de Postgres (`/rest/v1/rpc/{nombre}`). */
export async function rpc<T>(nombre: string, parametros: Record<string, unknown>): Promise<T> {
  const { url, llave } = credenciales();
  const respuesta = await fetch(`${url}/rest/v1/rpc/${nombre}`, {
    method: "POST",
    headers: encabezados(llave),
    body: JSON.stringify(parametros),
  });
  if (!respuesta.ok) throw new Error(`${nombre} ${respuesta.status}: ${await respuesta.text()}`);
  return await respuesta.json() as T;
}

/** Filas de [tabla] con `columna in (valores)`. */
export async function seleccionar<T>(tabla: string, columna: string, valores: string[]): Promise<T[]> {
  if (valores.length === 0) return [];
  const { url, llave } = credenciales();
  const lista = valores.map((v) => `"${v.replace(/"/g, "")}"`).join(",");
  const respuesta = await fetch(`${url}/rest/v1/${tabla}?${columna}=in.(${encodeURIComponent(lista)})`, {
    headers: encabezados(llave),
  });
  if (!respuesta.ok) throw new Error(`${tabla} ${respuesta.status}: ${await respuesta.text()}`);
  return await respuesta.json() as T[];
}

/** Inserta o reemplaza [filas] (por la clave primaria). */
export async function guardar(tabla: string, filas: Record<string, unknown>[]): Promise<void> {
  if (filas.length === 0) return;
  const { url, llave } = credenciales();
  const respuesta = await fetch(`${url}/rest/v1/${tabla}`, {
    method: "POST",
    headers: encabezados(llave, { "Prefer": "resolution=merge-duplicates,return=minimal" }),
    body: JSON.stringify(filas),
  });
  if (!respuesta.ok) throw new Error(`${tabla} ${respuesta.status}: ${await respuesta.text()}`);
}
