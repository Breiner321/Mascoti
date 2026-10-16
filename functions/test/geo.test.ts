import { distanceBetween, geohashForLocation, geohashQueryBounds } from "geofire-common";
import { describe, expect, it } from "vitest";

import { geohash } from "../../supabase/functions/_shared/geohash.ts";

describe("geohash (RF-09)", () => {
  it("coincide con geofire-common (lo que usa geoflutterfire_plus en la app)", () => {
    const puntos: [number, number][] = [
      [4.711, -74.0721], // Bogotá
      [6.2442, -75.5812], // Medellín
      [-4.2, -69.94], // Leticia
      [12.58, -81.7], // San Andrés
      [0, 0],
      [-33.45, -70.66],
    ];
    for (const [lat, lng] of puntos) {
      expect(geohash(lat, lng)).toBe(geohashForLocation([lat, lng]));
    }
    expect(geohash(4.711, -74.0721)).toBe("d2g6f3w7df");
  });

  it("una clínica cercana cae dentro de una búsqueda de 10 km", () => {
    const hash = geohash(4.711, -74.0721);
    const centro: [number, number] = [4.65, -74.06]; // ~7 km al sur
    expect(distanceBetween([4.711, -74.0721], centro)).toBeLessThan(10);
    const dentro = geohashQueryBounds(centro, 10_000).some(
      ([inicio, fin]) => hash >= inicio && hash <= fin,
    );
    expect(dentro).toBe(true);
  });
});
