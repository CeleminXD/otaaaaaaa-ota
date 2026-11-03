# Publicación OTA del ESP32

Este repositorio aloja los Releases de firmware y el manifiesto que consultan los dispositivos. El código fuente y la compilación del ESP32 permanecen en el proyecto del dispositivo.

## Configuración del dispositivo

Configura en ESP-IDF menuconfig → Hi Tetranutras WiFi / OTA → HTTPS URL for the OTA manifest:

    https://raw.githubusercontent.com/CeleminXD/otaaaaaaa-ota/main/manifest.json

## Publicar una versión

1. En el proyecto ESP32, actualiza version.txt y compila con idf.py build.
2. Desde PowerShell, ejecuta en este repositorio (ajusta la versión):

    .\package-release.ps1 -EspProjectPath 'C:\Users\USUARIO\otaaaaaaa' -Version '1.0.9' -GitHubRepository 'CeleminXD/otaaaaaaa-ota'

3. En GitHub, crea un Release con etiqueta v1.0.9, adjunta el archivo dist/otaaaaaaa-v1.0.9.bin y publícalo.

Al publicarse un Release estable, la acción de GitHub valida la etiqueta y el asset, y actualiza manifest.json en main con la URL real del binario. Usa el nombre versionado que genera el empaquetador; se acepta otaaaaaaa.bin como compatibilidad con Releases anteriores. Revisa la ejecución en Actions. Si falla, el manifiesto anterior se conserva.

No subas manifest.json manualmente: la acción lo publica después de que el binario esté disponible. El workflow usa GITHUB_TOKEN con permiso contents: write; no necesita un token personal. Si GitHub bloquea la escritura, revisa Settings → Actions → General → Workflow permissions.

El manifiesto tiene este formato:

    {
      "version": "1.0.9",
      "url": "https://github.com/CeleminXD/otaaaaaaa-ota/releases/download/v1.0.9/otaaaaaaa-v1.0.9.bin"
    }

El dispositivo revisa el manifiesto al iniciar y luego cada hora. Solo instala una versión MAJOR.MINOR.PATCH superior a la instalada. Un Release publicado antes de crear el workflow no activa la acción retroactivamente.

## Primera instalación

La primera instalación se hace por USB con rollback habilitado, la URL estable del manifiesto configurada y una versión semántica en version.txt. Después, las versiones se distribuyen mediante Releases.

No publiques credenciales Wi-Fi, claves privadas ni archivos sdkconfig en este repositorio.
