// Edge Function vincular-mascota (semana 3). La clínica escribe el código de
// paciente (MSC-XXXX) que le da el dueño y queda autorizada para ver la
// mascota y su historial. La lógica está en ../_shared/vinculacion.ts.
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { ErrorFuncion } from "../_shared/errores.ts";
import { agregarAArreglo } from "../_shared/firestore.ts";
import { commitFirestore, leerDocumentoFirestore, verificarTokenFirebase } from "../_shared/google.ts";
import { registrarIntentoVinculacion } from "../_shared/limite_intentos.ts";
import { MAX_INTENTOS, VENTANA_MINUTOS, vincularMascota } from "../_shared/vinculacion.ts";

const PROYECTO_FIREBASE = Deno.env.get("FIREBASE_PROJECT_ID") ?? "mascoti-b27cf";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function responder(estado: number, cuerpo: unknown): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return responder(405, { error: { code: "invalid-argument", message: "Usa POST" } });
  }

  try {
    const cuenta = () => leerCuentaServicio(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"));
    const cuerpo = await req.json().catch(() => null);

    const resultado = await vincularMascota(
      {
        verificarToken: (token) => verificarTokenFirebase(token, PROYECTO_FIREBASE),
        leer: (ruta) => leerDocumentoFirestore(cuenta(), ruta),
        registrarIntento: (clinicId) =>
          registrarIntentoVinculacion(clinicId, MAX_INTENTOS, VENTANA_MINUTOS),
        autorizarClinica: async (petId, clinicId) => {
          await commitFirestore(cuenta(), [
            agregarAArreglo(PROYECTO_FIREBASE, `pets/${petId}`, "clinicasAutorizadas", [clinicId]),
          ]);
        },
      },
      req.headers.get("Authorization"),
      cuerpo,
    );
    return responder(200, resultado);
  } catch (e) {
    if (e instanceof ErrorFuncion) {
      return responder(e.estadoHttp, { error: { code: e.codigo, message: e.message } });
    }
    console.error(e);
    return responder(500, {
      error: { code: "internal", message: "No se pudo vincular la mascota. Intenta de nuevo." },
    });
  }
});
