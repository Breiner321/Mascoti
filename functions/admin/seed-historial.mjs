// RF-08: datos de ejemplo del historial médico, SOLO en el emulador de
// Firestore (nunca en Firebase real). Ver docs/datos-prueba.md.
//
// Crea para el usuario <uid> (el que entró con Google en la app con
// USE_EMULATORS=true):
//   - users/{uid} como dueño, con el onboarding visto (completar-registro no
//     acepta usuarios del emulador de Auth);
//   - la clínica "Clínica Veterinaria Demo" (activa);
//   - la mascota "Toby" con código de paciente y la clínica autorizada;
//   - 3 consultas: con vacunas (una con próxima dosis), con adjuntos (imagen
//     y PDF, que no existen en Supabase: se ven como "Archivo no disponible")
//     y una de hace un año.
// Se puede correr varias veces: reemplaza los mismos documentos.
//
// Uso (desde functions/, con `firebase emulators:start` corriendo):
//   npm run seed:historial -- <uid>
//   npm run seed:historial -- <uid> --nueva   → agrega una consulta de hoy
//                                               (para ver el tiempo real)
import { initializeApp } from "firebase-admin/app";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";

const [uid, opcion] = process.argv.slice(2);
if (!uid || (opcion && opcion !== "--nueva")) {
  console.error("Uso: npm run seed:historial -- <uid> [--nueva]");
  process.exit(1);
}

// Sin esta variable firebase-admin escribiría en el proyecto real.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("Este script es solo para el emulador: quita GOOGLE_APPLICATION_CREDENTIALS.");
  process.exit(1);
}

initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? "mascoti-b27cf" });
const db = getFirestore();

const clinicId = "clinica-demo";
const petId = `${uid}-toby`;
const codigo = "MSC-DEMQ"; // alfabeto de PatientCode: sin 0/O, 1/I ni L
const dias = (n) => Timestamp.fromDate(new Date(Date.now() - n * 24 * 60 * 60 * 1000));
const enDias = (n) => Timestamp.fromDate(new Date(Date.now() + n * 24 * 60 * 60 * 1000));
const registros = db.collection("pets").doc(petId).collection("medicalRecords");

if (opcion === "--nueva") {
  const ref = registros.doc();
  await ref.set({
    clinicId,
    clinicNombre: "Clínica Veterinaria Demo",
    fecha: Timestamp.now(),
    diagnostico: "Control de seguimiento: evolución favorable",
    tratamiento: "Continuar dieta blanda dos días más.",
    vacunas: [],
    adjuntos: [],
    createdAt: FieldValue.serverTimestamp(),
  });
  console.log(`Consulta nueva pets/${petId}/medicalRecords/${ref.id}`);
  process.exit(0);
}

const batch = db.batch();

batch.set(db.doc(`users/${uid}`), {
  uid,
  email: "dueno.demo@mascoti.test",
  displayName: "Dueño Demo",
  photoURL: null,
  role: "dueno",
  estado: "activo",
  clinicId: null,
  onboardingVisto: true,
  createdAt: FieldValue.serverTimestamp(),
  lastLoginAt: FieldValue.serverTimestamp(),
});

batch.set(db.doc(`clinics/${clinicId}`), {
  ownerUid: "clinica-demo-owner",
  nombre: "Clínica Veterinaria Demo",
  direccion: "Calle 10 # 43-12, Medellín",
  lat: 6.2088,
  lng: -75.5674,
  telefono: "6041234567",
  tiposAnimales: ["perros", "gatos"],
  atencionEmergencias: true,
  estado: "activo",
  createdAt: FieldValue.serverTimestamp(),
});

batch.set(db.doc(`pets/${petId}`), {
  ownerUid: uid,
  nombre: "Toby",
  especie: "perro",
  raza: "Criollo",
  sexo: "macho",
  fechaNacimiento: Timestamp.fromDate(new Date(2022, 4, 12)),
  fotoPath: null,
  codigoPaciente: codigo,
  clinicasAutorizadas: [clinicId],
  alergias: ["Pollo"],
  condiciones: [],
  contactoEmergencia: { nombre: "Ana Pérez", telefono: "3001234567" },
  createdAt: FieldValue.serverTimestamp(),
});
batch.set(db.doc(`codigosPaciente/${codigo}`), {
  petId,
  ownerUid: uid,
  createdAt: FieldValue.serverTimestamp(),
});

const consultas = [
  {
    id: "demo-vacunas",
    fecha: dias(3),
    diagnostico: "Control anual: paciente sano",
    tratamiento: "Desparasitación interna con dosis única.",
    vacunas: [
      { nombre: "Rabia", lote: "RB-2026-114", fechaAplicacion: dias(3), fechaProximaDosis: enDias(362) },
      { nombre: "Parvovirus", lote: "PV-7781", fechaAplicacion: dias(3) },
    ],
    adjuntos: [],
  },
  {
    id: "demo-adjuntos",
    fecha: dias(40),
    diagnostico: "Cojera en pata trasera izquierda",
    tratamiento: "Antiinflamatorio por 5 días y reposo.",
    vacunas: [],
    adjuntos: [
      { path: `${petId}/demo-adjuntos/radiografia.jpg`, tipo: "imagen", nombre: "radiografia.jpg" },
      { path: `${petId}/demo-adjuntos/examen.pdf`, tipo: "pdf", nombre: "examen.pdf" },
    ],
  },
  {
    id: "demo-antigua",
    fecha: dias(365),
    diagnostico: "Gastroenteritis leve",
    tratamiento: "",
    vacunas: [],
    adjuntos: [],
  },
];
for (const { id, ...datos } of consultas) {
  batch.set(registros.doc(id), {
    clinicId,
    clinicNombre: "Clínica Veterinaria Demo",
    ...datos,
    createdAt: datos.fecha,
  });
}
batch.set(db.doc(`vacunasProgramadas/demo-vacunas_0`), {
  petId,
  ownerUid: uid,
  clinicId,
  recordId: "demo-vacunas",
  vacuna: "Rabia",
  fechaProximaDosis: enDias(362),
  notificado: false,
  createdAt: FieldValue.serverTimestamp(),
});

await batch.commit();
console.log(`Listo: mascota "Toby" (pets/${petId}, ${codigo}) con 3 consultas.`);
