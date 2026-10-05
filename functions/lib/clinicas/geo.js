"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.geoClinica = geoClinica;
const firestore_1 = require("firebase-admin/firestore");
const geofire_common_1 = require("geofire-common");
/** Calcula `geo` a partir de lat/lng. Devuelve null si falta alguna coordenada. */
function geoClinica(lat, lng) {
    if (lat === null || lng === null)
        return null;
    return {
        geohash: (0, geofire_common_1.geohashForLocation)([lat, lng]),
        geopoint: new firestore_1.GeoPoint(lat, lng),
    };
}
//# sourceMappingURL=geo.js.map