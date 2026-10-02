import { GeoPoint } from "firebase-admin/firestore";
import { geohashForLocation } from "geofire-common";

/** Campo `geo` de clinics/{id}, en el formato que lee geoflutterfire_plus (RF-09). */
export interface GeoClinica {
  geohash: string;
  geopoint: GeoPoint;
}

/** Calcula `geo` a partir de lat/lng (ya validados por validarRegistro). */
export function geoClinica(lat: number, lng: number): GeoClinica {
  return {
    geohash: geohashForLocation([lat, lng]),
    geopoint: new GeoPoint(lat, lng),
  };
}
