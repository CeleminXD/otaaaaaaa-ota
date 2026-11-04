# Publicación OTA del ESP32

Este repositorio aloja los Releases del firmware y el manifiesto que consultan los dispositivos. El proyecto ESP queda separado en `otaaaaaaa`.

## Publicar desde VS Code

1. Autoriza GitHub CLI una sola vez con la cuenta `CeleminXD`:

   ```powershell
   gh auth login --hostname github.com --web --git-protocol https
   ```

2. En el proyecto ESP, abre la paleta de comandos (`Ctrl+Shift+P`) y selecciona **Tasks: Run Task** → **OTA: Publicar y actualizar firmware**.

La tarea asigna la siguiente versión de parche, compila el firmware con ESP-IDF, valida y adjunta el `.bin` y su `.sha256` a un Release, lo publica y espera a que GitHub Actions verifique ambos y actualice `manifest.json`. También puedes ejecutarlo directamente:

```powershell
& 'C:\Users\USUARIO\otaaaaaaa-ota\publish-ota.ps1' -EspProjectPath 'C:\Users\USUARIO\otaaaaaaa'
```

La primera vez puede requerir aprobar el acceso de GitHub CLI en el navegador. El publicador comprueba que estés usando `CeleminXD` y que el Release y el manifiesto anterior estén sincronizados; si detecta un estado inconsistente, se detiene para no publicar una versión incorrecta.

Antes de compilar, el publicador comprueba que la clave privada de firma exista y esté fuera de ambos repositorios. Mantén esa clave en almacenamiento privado y con copia de seguridad; nunca la subas a GitHub ni la incluyas en `dist`.

Antes de publicar una versión, sincroniza estos cambios con la rama `main` del repositorio OTA. El publicador verifica que el workflow remoto ya compruebe el checksum y los metadatos; si aún no está actualizado, se detiene antes de publicar.

## Manifiesto del dispositivo

Configura en ESP-IDF menuconfig → Hi Tetranutras WiFi / OTA → HTTPS URL for the OTA manifest:

```text
https://raw.githubusercontent.com/CeleminXD/otaaaaaaa-ota/main/manifest.json
```

Al publicarse un Release estable, el workflow valida la versión y el `.bin`, y actualiza el manifiesto en `main`. No subas `manifest.json` manualmente. El workflow usa `GITHUB_TOKEN` con permiso `contents: write`; si GitHub bloquea la escritura, revisa **Settings → Actions → General → Workflow permissions**.

El manifiesto tiene este formato:

```json
{
  "version": "1.0.9",
  "url": "https://github.com/CeleminXD/otaaaaaaa-ota/releases/download/v1.0.9/otaaaaaaa-v1.0.9.bin",
  "model": "otaaaaaaa",
  "target": "esp32c6",
  "sha256": "SHA-256 real de los bytes completos del .bin publicado"
}
```

El empaquetador calcula el SHA-256 del `.bin` firmado y adjunta un archivo `.sha256`. GitHub Actions descarga ambos assets y detiene la publicación del manifiesto si el hash no coincide. El ESP compara `model` con el nombre del proyecto y `target` con el chip compilado, y verifica el hash desde la partición OTA antes de seleccionar esa imagen. Los valores actuales son `otaaaaaaa` y `esp32c6`; para otro producto/chip se requiere compilar una imagen compatible y publicar un manifiesto destinado a ese modelo.

El dispositivo revisa el manifiesto al iniciar y luego cada hora. La publicación en GitHub no fuerza una instalación instantánea: el ESP descarga el firmware al iniciar o en su siguiente revisión OTA, si la versión remota es superior.

## Primera instalación y seguridad

La primera instalación se hace por USB con rollback habilitado y la URL estable del manifiesto configurada. No publiques credenciales Wi-Fi, claves privadas ni archivos `sdkconfig` en este repositorio.
