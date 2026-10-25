#!/usr/bin/env python3
"""
save-sync: sincroniza partidas guardadas de juegos sin nube entre varios
ordenadores usando una carpeta de nube (OneDrive, Google Drive, Dropbox...).

Funcionamiento: la carpeta de guardado de cada juego se mueve a la carpeta
de nube y en su sitio se deja un enlace (junction en Windows, symlink en
Linux/macOS). El juego sigue guardando "en local", pero los archivos viven
en la nube y el cliente de sincronización los sube y baja solo.

Uso:
    python save_sync.py setup     # enlaza todos los juegos del config
    python save_sync.py status    # muestra el estado de cada juego
    python save_sync.py unlink    # deshace el enlace y deja copia local
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

IS_WINDOWS = os.name == "nt"
DEFAULT_CONFIG = Path(__file__).with_name("config.json")


# ---------------------------------------------------------------- utilidades

def expand(p: str) -> Path:
    """Expande variables (%USERPROFILE%, $HOME, ~) y devuelve ruta absoluta."""
    return Path(os.path.expandvars(os.path.expanduser(p))).absolute()


def load_config(path: Path) -> dict:
    if not path.exists():
        sys.exit(f"No encuentro {path}. Copia config.example.json a config.json y edítalo.")
    with path.open(encoding="utf-8") as f:
        cfg = json.load(f)
    if "cloud_dir" not in cfg or "games" not in cfg:
        sys.exit("El config necesita 'cloud_dir' y 'games'.")
    return cfg


def link_target(p: Path):
    """Si p es un enlace (symlink o junction), devuelve su destino; si no, None."""
    try:
        return Path(os.readlink(p)).absolute()
    except (OSError, ValueError):
        return None


def same_path(a: Path, b: Path) -> bool:
    norm = lambda x: os.path.normcase(os.path.normpath(str(x))).removeprefix("\\\\?\\")
    return norm(a) == norm(b)


def make_link(local: Path, cloud: Path) -> None:
    local.parent.mkdir(parents=True, exist_ok=True)
    if IS_WINDOWS:
        # Junction: no necesita permisos de administrador.
        r = subprocess.run(["cmd", "/c", "mklink", "/J", str(local), str(cloud)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise OSError(r.stderr.strip() or r.stdout.strip())
    else:
        os.symlink(cloud, local, target_is_directory=True)


def remove_link(local: Path) -> None:
    # Borra solo el enlace, nunca el contenido al que apunta.
    if IS_WINDOWS:
        os.rmdir(local)
    else:
        local.unlink()


def pin_offline(cloud: Path) -> None:
    """En OneDrive, marca la carpeta como 'Mantener siempre en este dispositivo'."""
    if IS_WINDOWS:
        subprocess.run(["attrib", "+P", "-U", "/S", "/D", str(cloud)],
                       capture_output=True)


def last_modified(folder: Path) -> str:
    newest = 0.0
    for root, _, files in os.walk(folder):
        for name in files:
            try:
                newest = max(newest, os.path.getmtime(os.path.join(root, name)))
            except OSError:
                pass
    return datetime.fromtimestamp(newest).strftime("%d/%m/%Y %H:%M") if newest else "vacía"


# ---------------------------------------------------------------- comandos

def setup_game(name: str, local: Path, cloud: Path, pin: bool) -> None:
    target = link_target(local)

    if target is not None:
        if same_path(target, cloud):
            print(f"[OK]     {name}: ya estaba enlazado.")
            return
        sys.exit(f"[ERROR]  {name}: {local} ya es un enlace a {target}. Revísalo a mano.")

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")

    if local.exists() and not cloud.exists():
        # Primer ordenador: las partidas locales pasan a la nube.
        cloud.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(local), str(cloud))
        print(f"[MOVIDO] {name}: partidas subidas a {cloud}")
    elif local.exists() and cloud.exists():
        # Segundo ordenador: manda la nube; lo local se guarda como copia.
        backup = local.with_name(f"{local.name}.backup-{stamp}")
        shutil.move(str(local), str(backup))
        print(f"[COPIA]  {name}: partidas locales guardadas en {backup}")
    else:
        cloud.mkdir(parents=True, exist_ok=True)

    make_link(local, cloud)
    if pin:
        pin_offline(cloud)
    print(f"[OK]     {name}: {local} -> {cloud}")


def cmd_setup(cfg: dict) -> None:
    cloud_root = expand(cfg["cloud_dir"])
    if not cloud_root.parent.exists():
        sys.exit(f"No existe {cloud_root.parent}. ¿Está instalado y abierto el cliente de nube?")
    for g in cfg["games"]:
        setup_game(g["name"], expand(g["path"]), cloud_root / g["name"],
                   cfg.get("pin_onedrive", True))


def cmd_status(cfg: dict) -> None:
    cloud_root = expand(cfg["cloud_dir"])
    for g in cfg["games"]:
        name, local, cloud = g["name"], expand(g["path"]), cloud_root / g["name"]
        target = link_target(local)
        if target is not None and same_path(target, cloud):
            estado = f"enlazado, último guardado {last_modified(cloud)}"
        elif target is not None:
            estado = f"enlace a otra ruta ({target})"
        elif local.exists():
            estado = "sin enlazar (ejecuta setup)"
        else:
            estado = "no existe la carpeta local"
        print(f"{name:<25} {estado}")


def cmd_unlink(cfg: dict) -> None:
    cloud_root = expand(cfg["cloud_dir"])
    for g in cfg["games"]:
        name, local, cloud = g["name"], expand(g["path"]), cloud_root / g["name"]
        target = link_target(local)
        if target is None or not same_path(target, cloud):
            print(f"[--]     {name}: no estaba enlazado.")
            continue
        remove_link(local)
        shutil.copytree(cloud, local)
        print(f"[OK]     {name}: copia local restaurada en {local}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Sincroniza partidas guardadas mediante una carpeta de nube.")
    ap.add_argument("command", choices=["setup", "status", "unlink"])
    ap.add_argument("-c", "--config", type=Path, default=DEFAULT_CONFIG)
    args = ap.parse_args()
    cfg = load_config(args.config)
    {"setup": cmd_setup, "status": cmd_status, "unlink": cmd_unlink}[args.command](cfg)


if __name__ == "__main__":
    main()
