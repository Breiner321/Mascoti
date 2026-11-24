// Página pública de la placa QR (RF-17): /q/{qrId}. Consulta la Edge Function
// placa-publica (Supabase, sin sesión) y muestra solo lo que el dueño eligió.
// No hay datos de la mascota en el HTML: todo llega de la función.
"use strict";

const FUNCION = "https://tahnazumbqsupzpusrba.supabase.co/functions/v1/placa-publica";

const $ = (id) => document.getElementById(id);

function qrIdDeLaUrl() {
  const partes = window.location.pathname.split("/").filter(Boolean);
  const id = partes[0] === "q" ? partes[1] : null;
  return id && /^[A-Za-z0-9]{10,40}$/.test(id) ? id : null;
}

async function consultar(qrId, revelar) {
  const respuesta = await fetch(FUNCION, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(revelar ? { qrId, revelar: true } : { qrId }),
  });
  const cuerpo = await respuesta.json().catch(() => ({}));
  return { estado: respuesta.status, cuerpo };
}

function mostrarSolo(id) {
  for (const seccion of ["ficha", "no-activa", "error"]) $(seccion).hidden = seccion !== id;
  $("cargando").hidden = true;
  $("contenido").setAttribute("aria-busy", "false");
}

function pintarFicha(f) {
  document.title = `${f.nombre} · Placa Mascoti`;
  $("nombre").textContent = f.nombre;
  $("especie").textContent = f.especie;

  if (f.fotoUrl) {
    $("foto").src = f.fotoUrl;
    $("foto").alt = `Foto de ${f.nombre}`;
    $("foto").hidden = false;
  }
  if (f.mensaje) {
    $("mensaje").textContent = f.mensaje;
    $("bloque-mensaje").hidden = false;
  }
  if (Array.isArray(f.alergias)) {
    const lista = $("alergias");
    lista.replaceChildren();
    const items = f.alergias.length > 0 ? f.alergias : ["Sin alergias registradas"];
    for (const a of items) {
      const li = document.createElement("li");
      li.textContent = a;
      lista.append(li);
    }
    $("bloque-alergias").hidden = false;
  }
  if (f.nombreDueno) {
    $("nombre-dueno").textContent = f.nombreDueno;
    $("bloque-dueno").hidden = false;
  }
  if (f.telefonoEnmascarado) {
    $("telefono").textContent = f.telefonoEnmascarado;
    $("telefono").setAttribute("aria-label", "Teléfono oculto. Pulsa Ver teléfono para verlo.");
    $("bloque-telefono").hidden = false;
  }
  mostrarSolo("ficha");
}

function formatear(t) {
  return t.length === 10 ? `${t.slice(0, 3)} ${t.slice(3, 6)} ${t.slice(6)}` : t;
}

async function verTelefono(qrId) {
  const boton = $("ver-telefono");
  const error = $("error-telefono");
  boton.disabled = true;
  error.hidden = true;
  try {
    const { estado, cuerpo } = await consultar(qrId, true);
    if (estado === 200 && cuerpo.telefono) {
      $("telefono").textContent = formatear(cuerpo.telefono);
      $("telefono").removeAttribute("aria-label");
      const llamar = $("llamar");
      llamar.href = `tel:+57${cuerpo.telefono}`;
      llamar.setAttribute("aria-label", `Llamar al ${formatear(cuerpo.telefono)}`);
      llamar.hidden = false;
      boton.hidden = true;
      llamar.focus();
      return;
    }
    error.textContent = cuerpo?.error?.message ?? "No pudimos mostrar el teléfono. Intenta de nuevo.";
  } catch {
    error.textContent = "No pudimos mostrar el teléfono. Revisa tu conexión.";
  }
  error.hidden = false;
  boton.disabled = false;
}

async function cargar() {
  const qrId = qrIdDeLaUrl();
  if (!qrId) return mostrarSolo("no-activa");
  $("cargando").hidden = false;
  $("contenido").setAttribute("aria-busy", "true");
  try {
    const { estado, cuerpo } = await consultar(qrId, false);
    if (estado === 200) {
      pintarFicha(cuerpo);
      $("ver-telefono").onclick = () => verTelefono(qrId);
    } else if (estado === 404) {
      mostrarSolo("no-activa");
    } else {
      mostrarSolo("error");
    }
  } catch {
    mostrarSolo("error");
  }
}

$("reintentar").addEventListener("click", cargar);
cargar();
