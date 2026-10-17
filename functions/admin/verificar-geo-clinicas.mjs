// Semana 3 (RF-09): revisa que todas las clínicas tengan `geo`
// {geohash, geopoint} coherente con lat/lng. Sin `geo` una clínica no
// aparece en el directorio con mapa.
//
// Uso (desde functions/), con la cuenta de servicio FUERA del repo:
//   PowerShell:  $env:GOOGLE_APPLICATION_CREDENTIALS="C:\ruta\cuenta-servicio.json"
//   npm run verificar-geo               → solo informa (no cambia nada)
//   npm run verificar-geo -- --corregir → recalcula geo a partir de lat/lng
import { initializeApp } from "firebase-admin/app";
import { GeoPoint, getFirestore } from "firebase-admin/firestore";
import { geohashForLocation } from "geofire-common";

const corregir = process.argv.includes("--corregir");
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("Define GOOGLE_APPLICATION_CREDENTIALS con la ruta de la cuenta de servicio.");
  process.exit(1);
}

initializeApp();
const db = getFirestore();
const clinicas = await db.collection("clinics").get();

let bien = 0;
const porCorregir = [];
const sinCoordenadas = [];
for (const doc of clinicas.docs) {
  const { lat, lng, geo, nombre } = doc.data();
  if (typeof lat !== "number" || typeof lng !== "number") {
    sinCoordenadas.push(`${doc.id} (${nombre ?? "sin nombre"})`);
    continue;
  }
  const esperado = geohashForLocation([lat, lng], 10);
  const coherente = geo?.geopoint?.latitude === lat && geo?.geopoint?.longitude === lng &&
    typeof geo?.geohash === "string" && esperado.startsWith(geo.geohash.slice(0, 9));
  if (coherente) {
    bien++;
  } else {
    porCorregir.push({ ref: doc.ref, id: doc.id, nombre, lat, lng, esperado });
  }
}

console.log(`Clínicas: ${clinicas.size} · con geo correcto: ${bien} · por corregir: ${porCorregir.length} · sin lat/lng: ${sinCoordenadas.length}`);
for (const c of porCorregir) console.log(`  - ${c.id} (${c.nombre ?? "sin nombre"})`);
if (sinCoordenadas.length) {
  console.log("Sin coordenadas (deben escoger su dirección de nuevo en la app):");
  for (const c of sinCoordenadas) console.log(`  - ${c}`);
}

if (corregir && porCorregir.length) {
  const lote = db.batch();
  for (const c of porCorregir) {
    lote.update(c.ref, { geo: { geohash: c.esperado, geopoint: new GeoPoint(c.lat, c.lng) } });
  }
  await lote.commit();
  console.log(`Corregidas: ${porCorregir.length}`);
} else if (porCorregir.length) {
  console.log("Para corregirlas: npm run verificar-geo -- --corregir");
}
