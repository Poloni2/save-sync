# save-sync

Sincroniza las partidas guardadas de juegos **sin nube propia** entre varios ordenadores Windows, usando OneDrive, Google Drive o Dropbox.

Juegas en un PC, cierras el juego, y en el otro sigues donde lo dejaste. No hay que copiar nada a mano ni instalar nada: funciona con PowerShell, que ya viene con Windows.

## Cómo funciona

1. La carpeta de guardado del juego se mueve a una carpeta de la nube (`OneDrive\SaveSync\Partidas\NOMBRE`).
2. En su sitio se deja un enlace (*junction*). El juego cree que guarda en local, pero los archivos están en la nube.
3. La **lista de juegos** (`games.json`) también está en la nube. Si añades un juego desde un PC, aparece en todos.
4. Cada PC guarda su propia ruta para cada juego. Si un juego guarda en `%APPDATA%` o `%USERPROFILE%`, la ruta sirve automáticamente en los demás PC.

## Instalación

1. Descarga el repositorio (botón verde **Code → Download ZIP**) y descomprímelo en una carpeta fija, por ejemplo `Documentos\save-sync`.
2. Doble clic en **`SaveSync.bat`**.
3. La primera vez detecta OneDrive y te pregunta si usar esa carpeta. Si usas otra nube, elige su carpeta.

No hacen falta permisos de administrador.

## Menú

| Opción | Qué hace |
|---|---|
| 1. Añadir juego | Eliges la carpeta de partidas del juego. Se sube a la nube y se enlaza. Si el juego ya está en la lista (añadido desde otro PC), escribe el mismo nombre para añadir la ruta de este PC. |
| 2. Sincronizar este PC | Enlaza en este PC todos los juegos de la lista. Úsalo en el segundo PC o después de añadir juegos desde el otro. |
| 3. Ver estado | Muestra cada juego, si está enlazado aquí, la fecha del último guardado y en qué PC está registrado. |
| 4. Sincronizar al iniciar Windows | Hace la opción 2 sola al encender el PC, en segundo plano. |
| 5. Deshacer enlace | Quita el enlace en este PC y deja una copia local de las partidas. |

También se puede usar por línea de comandos: `SaveSync.bat add|sync|status|unlink|autostart`.

## Qué pasa con las partidas que ya existen

- **El juego aún no está en la nube:** las partidas de este PC se suben.
- **La nube ya tiene partidas de ese juego:** mandan las de la nube. Las de este PC no se borran: se renombran a `CARPETA.backup-FECHA`.
- **El juego no está instalado en este PC:** se salta, sin error.

## Dónde guardan algunos juegos

| Juego / motor | Carpeta |
|---|---|
| Fangames de Pokémon Essentials (versiones nuevas) | `%APPDATA%\NOMBRE_DEL_JUEGO` |
| Fangames de RPG Maker XP (versiones antiguas) | `%USERPROFILE%\Saved Games\NOMBRE_DEL_JUEGO` |
| Ryujinx (Switch) | `%APPDATA%\Ryujinx\bis\user\save` |
| Muchos juegos de Steam sin Steam Cloud | `%APPDATA%`, `%LOCALAPPDATA%` o `Documentos\My Games` |

Si un juego de Steam tiene **Steam Cloud**, no lo añadas: ya se sincroniza solo. Los logros y las horas de Steam van siempre en tu cuenta.

## Reglas para no perder partidas

- No juegues al mismo juego en los dos PC a la vez.
- Antes de apagar, espera a que OneDrive termine de subir (icono de la nube sin flechas).
- Antes de abrir el juego en el otro PC, espera a que termine de bajar.

Hay un registro de lo que hace la app en `%APPDATA%\save-sync\save-sync.log`.

## Licencia

MIT. Ver [LICENSE](LICENSE).
