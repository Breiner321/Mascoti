import { GeoPoint } from "firebase-admin/firestore";
import { geohashForLocation } from "geofire-common";

/** Campo `geo` de clinics/{id}, en el formato que lee geoflutterfire_plus (RF-09). */
export interface GeoClinica {
  geohash: string;
  geopoint: GeoPoint;
}

/** Calcula `geo` a partir de lat/lng. Devuelve null si falta alguna coordenada. */
export function geoClinica(lat: number | null, lng: number | null): GeoClinica | null {
  if (lat === null || lng === null) return null;
  return {
    geohash: geohashForLocation([lat, lng]),
    geopoint: new GeoPoint(lat, lng),
  };
}
