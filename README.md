# Publicación OTA del proyecto ESP32

Este repositorio aloja el manifiesto de actualización y organiza los binarios
publicados. El código fuente y la compilación del ESP32 siguen en el proyecto
del dispositivo; este repositorio es independiente.

## Alojamiento

1. Crea un repositorio público en GitHub llamado `otaaaaaaa-ota` y sube el
   contenido de este repositorio.
2. Conserva `manifest.json` en la raíz como URL estable para los dispositivos:
   `https://raw.githubusercontent.com/OWNER/otaaaaaaa-ota/main/manifest.json`.
3. En el proyecto ESP32, configura esa URL en `idf.py menuconfig` →
   **Hi Tetranutras WiFi / OTA** → **HTTPS URL for the OTA manifest**. Debe
   tener menos de 200 caracteres.

Reemplaza `OWNER` con tu nombre de usuario u organización de GitHub. No
configures el URL de ejemplo en los dispositivos.

## Publicar una versión

Abre una terminal con ESP-IDF activado y ejecuta desde este repositorio:

```powershell
.\package-release.ps1 `
  -EspProjectPath 'C:\ruta\al\proyecto\esp32' `
  -Version '1.0.1' `
  -GitHubRepository 'OWNER/otaaaaaaa-ota'
```

Antes, cambia `version.txt` en el proyecto ESP32 al mismo valor y ejecuta
`idf.py build`. El empaquetador comprueba que el binario se haya generado
después del cambio de versión. Produce:

- `dist/otaaaaaaa-v1.0.1.bin`, para adjuntar al Release de GitHub.
- `manifest.json`, que se publica en la rama `main` después de que el asset
  del Release ya esté disponible.
- `dist/manifest.json`, copia del mismo manifiesto para revisar el paquete.

Crea un Release de GitHub con etiqueta `v1.0.1` y adjunta el `.bin`. Luego
confirma y sube `manifest.json` a `main`. Así los dispositivos solo ven la
nueva versión después de que su firmware ya se pueda descargar.

El manifiesto tiene este formato:

```json
{
  "version": "1.0.1",
  "url": "https://github.com/OWNER/otaaaaaaa-ota/releases/download/v1.0.1/otaaaaaaa-v1.0.1.bin"
}
```

La aplicación consulta el manifiesto al iniciar OTA y luego cada hora. Si la
red o el servidor no responden, vuelve a intentar al minuto. Solo instala
una versión `MAJOR.MINOR.PATCH` superior a la que ya está ejecutando.

## Primera instalación

El dispositivo debe recibir inicialmente por USB una compilación del
proyecto ESP32 que tenga rollback habilitado, la URL estable del manifiesto
configurada y una versión semántica en `version.txt`. Después, las nuevas
versiones se distribuyen mediante los Releases.

No publiques credenciales Wi-Fi, claves privadas ni archivos `sdkconfig` en
este repositorio.
