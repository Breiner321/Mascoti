const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/**
 * Geohash estándar (el mismo de geofire-common / geoflutterfire_plus, RF-09).
 * Se implementa aquí para no depender de paquetes npm en la Edge Function.
 */
export function geohash(lat: number, lng: number, precision = 10): string {
  let latMin = -90, latMax = 90, lngMin = -180, lngMax = 180;
  let hash = "";
  let bits = 0;
  let valor = 0;
  let esLongitud = true;

  while (hash.length < precision) {
    if (esLongitud) {
      const mitad = (lngMin + lngMax) / 2;
      if (lng > mitad) {
        valor = valor * 2 + 1;
        lngMin = mitad;
      } else {
        valor = valor * 2;
        lngMax = mitad;
      }
    } else {
      const mitad = (latMin + latMax) / 2;
      if (lat > mitad) {
        valor = valor * 2 + 1;
        latMin = mitad;
      } else {
        valor = valor * 2;
        latMax = mitad;
      }
    }
    esLongitud = !esLongitud;
    if (++bits === 5) {
      hash += BASE32[valor];
      bits = 0;
      valor = 0;
    }
  }
  return hash;
}
