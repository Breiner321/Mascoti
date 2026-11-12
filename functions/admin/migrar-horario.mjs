// Cambio 2: convierte `horarioBase` {apertura, cierre, duracionSlotMin} en
// `horarioSemanal` (todos los días abiertos con el mismo horario, decisión
// del equipo: nada cambia para la clínica) y `reservas` con los valores por
// defecto. No borra `horarioBase` (versiones viejas de la app lo leen). Se
// puede ejecutar varias veces: salta las clínicas que ya tienen horarioSemanal.
//
// Uso (desde functions/), con la cuenta de servicio FUERA del repo:
//   PowerShell:  $env:GOOGLE_APPLICATION_CREDENTIALS="C:\ruta\cuenta-servicio.json"
//   npm run migrar-horario               → solo informa (no cambia nada)
//   npm run migrar-horario -- --aplicar  → escribe los cambios
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const aplicar = process.argv.includes("--aplicar");
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("Define GOOGLE_APPLICATION_CREDENTIALS con la ruta de la cuenta de servicio.");
  process.exit(1);
}

const DIAS = ["lun", "mar", "mie", "jue", "vie", "sab", "dom"];

/** La duración vieja podía ser 5-480; la nueva solo 15, 30 o 60. */
function duracionPermitida(min) {
  if (typeof min !== "number") return 30;
  return [15, 30, 60].reduce((mejor, d) => (Math.abs(d - min) < Math.abs(mejor - min) ? d : mejor), 30);
}

initializeApp();
const db = getFirestore();
const clinicas = await db.collection("clinics").get();

const porMigrar = [];
let yaMigradas = 0;
const sinHorario = [];
for (const doc of clinicas.docs) {
  const { horarioBase, horarioSemanal, reservas, nombre } = doc.data();
  if (horarioSemanal) {
    yaMigradas++;
    continue;
  }
  if (!horarioBase?.apertura || !horarioBase?.cierre) {
    sinHorario.push(`${doc.id} (${nombre ?? "sin nombre"})`);
    continue;
  }
  const dia = { abierto: true, apertura: horarioBase.apertura, cierre: horarioBase.cierre };
  porMigrar.push({
    ref: doc.ref,
    id: doc.id,
    nombre,
    cambios: {
      horarioSemanal: Object.fromEntries(DIAS.map((d) => [d, dia])),
      ...(reservas ? {} : {
        reservas: {
          duracionSlotMin: duracionPermitida(horarioBase.duracionSlotMin),
          anticipacionMaxDias: 30,
          anticipacionMinMin: 120,
        },
      }),
    },
  });
}

console.log(`Clínicas: ${clinicas.size} · ya migradas: ${yaMigradas} · por migrar: ${porMigrar.length} · sin horario: ${sinHorario.length}`);
for (const c of porMigrar) {
  const d = c.cambios.horarioSemanal.lun;
  console.log(`  - ${c.id} (${c.nombre ?? "sin nombre"}): todos los días ${d.apertura}-${d.cierre}`);
}
if (sinHorario.length) {
  console.log("Sin horario (lo configuran en su perfil de atención):");
  for (const c of sinHorario) console.log(`  - ${c}`);
}

if (aplicar && porMigrar.length) {
  // Lotes de máximo 500 escrituras.
  for (let i = 0; i < porMigrar.length; i += 500) {
    const lote = db.batch();
    for (const c of porMigrar.slice(i, i + 500)) lote.update(c.ref, c.cambios);
    await lote.commit();
  }
  console.log(`Migradas: ${porMigrar.length}`);
} else if (porMigrar.length) {
  console.log("Para aplicar: npm run migrar-horario -- --aplicar");
}
