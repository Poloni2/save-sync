# save-sync

Sincroniza las partidas guardadas de juegos **sin nube propia** entre varios ordenadores, usando una carpeta de OneDrive, Google Drive o Dropbox.

Juegas en un PC, cierras el juego, y en el otro PC sigues donde lo dejaste. Sin copiar archivos a mano.

## Cómo funciona

1. La carpeta de guardado del juego se mueve a una carpeta de la nube.
2. En su sitio original se crea un enlace (junction en Windows, symlink en Linux/macOS).
3. El juego cree que guarda en local, pero los archivos están en la nube y el cliente de sincronización los sube y baja solo.

## Requisitos

- Python 3.9 o superior.
- Un cliente de nube instalado y sincronizando en los dos ordenadores (OneDrive viene con Windows).
- No hacen falta permisos de administrador en Windows.

## Instalación

```
git clone https://github.com/TU_USUARIO/save-sync.git
cd save-sync
copy config.example.json config.json
```

Edita `config.json`:

| Campo | Qué es |
|---|---|
| `cloud_dir` | Carpeta de la nube donde se guardarán las partidas. |
| `pin_onedrive` | Si es `true`, marca la carpeta como "Mantener siempre en este dispositivo" en OneDrive. |
| `games` | Lista de juegos: `name` (nombre de la carpeta en la nube) y `path` (carpeta de guardado del juego). |

Se pueden usar variables como `%USERPROFILE%`, `%APPDATA%`, `%OneDrive%` o `~`.

## Uso

**Primer ordenador** (el que tiene las partidas):

```
python save_sync.py setup
```

Mueve las partidas a la nube y crea los enlaces.

**Segundo ordenador**: espera a que la nube termine de sincronizar y ejecuta lo mismo:

```
python save_sync.py setup
```

Si ese PC ya tenía partidas locales, no se borran: se renombran a `NOMBRE.backup-FECHA`.

**Comprobar el estado:**

```
python save_sync.py status
```

**Deshacer** (quita el enlace y deja una copia local de las partidas):

```
python save_sync.py unlink
```

## Dónde guardan algunos juegos

| Juego / motor | Carpeta |
|---|---|
| Fangames de RPG Maker XP / Pokémon Essentials | `%USERPROFILE%\Saved Games\NOMBRE_DEL_JUEGO` |
| Muchos juegos de Steam sin Steam Cloud | `%APPDATA%`, `%LOCALAPPDATA%` o `Documentos\My Games` |

Si un juego de Steam tiene **Steam Cloud**, no lo añadas: ya se sincroniza solo.

## Reglas para no perder partidas

- No juegues al mismo juego en los dos ordenadores a la vez.
- Antes de apagar, comprueba que la nube ha terminado de subir.
- Antes de abrir el juego en el otro PC, comprueba que la nube ha terminado de bajar.

## Licencia

MIT. Ver [LICENSE](LICENSE).
