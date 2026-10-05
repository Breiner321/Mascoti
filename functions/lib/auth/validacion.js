"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.validarRegistro = validarRegistro;
const https_1 = require("firebase-functions/v2/https");
const TELEFONO = /^\d{10}$/;
function invalido(mensaje) {
    throw new https_1.HttpsError("invalid-argument", mensaje);
}
function numeroONulo(valor, campo, limite) {
    if (valor === null || valor === undefined)
        return null;
    if (typeof valor !== "number" || !Number.isFinite(valor) || Math.abs(valor) > limite) {
        invalido(`${campo} inválido`);
    }
    return valor;
}
/** Valida el payload de completarRegistro con las reglas de RF-01 (paso 9-10). */
function validarRegistro(data) {
    if (typeof data !== "object" || data === null)
        invalido("Datos de registro vacíos");
    const { role, clinica } = data;
    if (role === "dueno")
        return { role: "dueno" };
    if (role !== "clinica")
        invalido("Selecciona un rol válido");
    if (typeof clinica !== "object" || clinica === null) {
        invalido("Faltan los datos de la clínica");
    }
    const c = clinica;
    const nombre = typeof c.nombre === "string" ? c.nombre.trim() : "";
    const telefono = typeof c.telefono === "string" ? c.telefono.trim() : "";
    const direccion = typeof c.direccion === "string" ? c.direccion.trim() : "";
    if (nombre.length < 3)
        invalido("El nombre comercial debe tener mínimo 3 caracteres");
    if (!TELEFONO.test(telefono))
        invalido("El teléfono debe tener 10 dígitos numéricos");
    if (direccion.length === 0)
        invalido("Selecciona una dirección válida de la lista");
    // TODO(RF-01): exigir lat/lng cuando la app use Google Places.
    const lat = numeroONulo(c.lat, "lat", 90);
    const lng = numeroONulo(c.lng, "lng", 180);
    return { role: "clinica", clinica: { nombre, telefono, direccion, lat, lng } };
}
//# sourceMappingURL=validacion.js.map