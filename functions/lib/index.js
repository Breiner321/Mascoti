"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sincronizarSuspension = exports.completarRegistro = void 0;
const app_1 = require("firebase-admin/app");
(0, app_1.initializeApp)();
// Exporta aquí cada Function nueva (una carpeta por módulo).
var completarRegistro_1 = require("./auth/completarRegistro");
Object.defineProperty(exports, "completarRegistro", { enumerable: true, get: function () { return completarRegistro_1.completarRegistro; } });
var sincronizarSuspension_1 = require("./auth/sincronizarSuspension");
Object.defineProperty(exports, "sincronizarSuspension", { enumerable: true, get: function () { return sincronizarSuspension_1.sincronizarSuspension; } });
//# sourceMappingURL=index.js.map