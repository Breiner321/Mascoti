import { GeoPoint } from "firebase-admin/firestore";
import { distanceBetween, geohashQueryBounds } from "geofire-common";
import { describe, expect, it } from "vitest";

import { geoClinica } from "../src/clinicas/geo";

describe("geoClinica (RF-09)", () => {
  it("calcula geohash y geopoint", () => {
    const geo = geoClinica(4.711, -74.0721); // Bogotá
    expect(geo?.geohash).toBe("d2g6f3w7df");
    expect(geo?.geopoint).toEqual(new GeoPoint(4.711, -74.0721));
  });

  it("queda dentro de una búsqueda de 10 km alrededor de un punto cercano", () => {
    const geo = geoClinica(4.711, -74.0721);
    const centro: [number, number] = [4.65, -74.06]; // ~7 km al sur
    expect(distanceBetween([4.711, -74.0721], centro)).toBeLessThan(10);
    const dentro = geohashQueryBounds(centro, 10_000).some(
      ([inicio, fin]) => geo.geohash >= inicio && geo.geohash <= fin,
    );
    expect(dentro).toBe(true);
  });
});
