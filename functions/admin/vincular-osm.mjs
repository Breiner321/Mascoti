// Cambio 4: guarda en cada clínica aliada el `osmId` del lugar de
// OpenStreetMap que le corresponde, para que el mapa no la muestre dos veces
// (como aliada y como "otra veterinaria"). Sin `osmId` la app igual las une
// si están a menos de 50 m y el nombre se parece; esto lo hace exacto.
//
// Busca veterinarias de OSM a 100 m de la clínica y elige la de nombre más
// parecido (≥ 0,5) a menos de 50 m: el mismo criterio de VetMatching
// (lib/core/domain/map_vet.dart). Salta las que ya tienen osmId.
//
// Uso (desde functions/), con la cuenta de servicio FUERA del repo:
//   PowerShell:  $env:GOOGLE_APPLICATION_CREDENTIALS="C:\ruta\cuenta-servicio.json"
//   npm run vincular-osm               → solo informa (no cambia nada)
//   npm run vincular-osm -- --aplicar  → escribe los osmId encontrados
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const aplicar = process.argv.includes("--aplicar");
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("Define GOOGLE_APPLICATION_CREDENTIALS con la ruta de la cuenta de servicio.");
  process.exit(1);
}

const OVERPASS = "https://overpass-api.de/api/interpreter";
const RADIO_BUSQUEDA_M = 100;
const MAX_METROS = 50;
const MIN_PARECIDO = 0.5;

// Igual que VetMatching._stopWords.
const COMUNES = new Set([
  "clinica", "veterinaria", "veterinario", "veterinarias", "vet", "centro", "hospital",
  "consultorio", "medico", "medica", "animal", "animales", "mascotas", "mascota", "pet", "pets",
  "de", "del", "la", "el", "los", "las", "y", "e", "sas", "ltda", "sa",
]);

const plano = (s) => s.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
const palabras = (s) =>
  new Set(plano(s).split(/[^a-z0-9]+/).filter((w) => w.length > 1 && !COMUNES.has(w)));

function parecido(a, b) {
  const ta = palabras(a);
  const tb = palabras(b);
  if (!ta.size || !tb.size) {
    const n = (s) => plano(s).replace(/[^a-z0-9]+/g, " ").trim();
    return n(a) === n(b) ? 1 : 0;
  }
  const comunes = [...ta].filter((w) => tb.has(w)).length;
  return comunes / Math.min(ta.size, tb.size);
}

function metros(lat1, lng1, lat2, lng2) {
  const rad = (d) => (d * Math.PI) / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lng2 - lng1) / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function veterinariasCerca(lat, lng) {
  const consulta = `[out:json][timeout:25];nwr["amenity"="veterinary"](around:${RADIO_BUSQUEDA_M},${lat},${lng});out center tags;`;
  const res = await fetch(OVERPASS, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "Mascoti/1.0 (vincular-osm)" },
    body: new URLSearchParams({ data: consulta }),
  });
  if (!res.ok) throw new Error(`Overpass respondió ${res.status}`);
  const { elements = [] } = await res.json();
  return elements
    .map((e) => ({
      osmId: `${e.type}/${e.id}`,
      nombre: e.tags?.name,
      lat: e.lat ?? e.center?.lat,
      lng: e.lon ?? e.center?.lon,
    }))
    .filter((v) => v.nombre && typeof v.lat === "number" && typeof v.lng === "number");
}

const esperar = (ms) => new Promise((r) => setTimeout(r, ms));

initializeApp();
const db = getFirestore();
const clinicas = await db.collection("clinics").get();

const encontradas = [];
const sinCoincidencia = [];
let yaVinculadas = 0;
for (const doc of clinicas.docs) {
  const { nombre, lat, lng, osmId } = doc.data();
  if (osmId) {
    yaVinculadas++;
    continue;
  }
  if (typeof lat !== "number" || typeof lng !== "number" || !nombre) {
    sinCoincidencia.push(`${doc.id} (${nombre ?? "sin nombre"}): sin ubicación`);
    continue;
  }
  let candidatas;
  try {
    candidatas = await veterinariasCerca(lat, lng);
  } catch (e) {
    sinCoincidencia.push(`${doc.id} (${nombre}): ${e.message}`);
    continue;
  }
  const mejor = candidatas
    .map((v) => ({ ...v, metros: metros(lat, lng, v.lat, v.lng), parecido: parecido(nombre, v.nombre) }))
    .filter((v) => v.metros < MAX_METROS && v.parecido >= MIN_PARECIDO)
    .sort((a, b) => b.parecido - a.parecido || a.metros - b.metros)[0];
  if (mejor) encontradas.push({ ref: doc.ref, id: doc.id, nombre, mejor });
  else sinCoincidencia.push(`${doc.id} (${nombre}): ninguna en OSM a menos de ${MAX_METROS} m con nombre parecido`);
  // Overpass es un servicio gratuito: una consulta por segundo.
  await esperar(1000);
}

console.log(`Clínicas: ${clinicas.size} · ya vinculadas: ${yaVinculadas} · encontradas: ${encontradas.length} · sin coincidencia: ${sinCoincidencia.length}`);
for (const c of encontradas) {
  console.log(`  - ${c.id} (${c.nombre}) → ${c.mejor.osmId} "${c.mejor.nombre}" a ${Math.round(c.mejor.metros)} m`);
}
if (sinCoincidencia.length) {
  console.log("Sin coincidencia (la app las une por cercanía y nombre si aparecen):");
  for (const c of sinCoincidencia) console.log(`  - ${c}`);
}

if (aplicar && encontradas.length) {
  const lote = db.batch();
  for (const c of encontradas) lote.update(c.ref, { osmId: c.mejor.osmId });
  await lote.commit();
  console.log(`Vinculadas: ${encontradas.length}`);
} else if (encontradas.length) {
  console.log("Para aplicar: npm run vincular-osm -- --aplicar");
}
