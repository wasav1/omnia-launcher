"""Desinstalación por usuario con lista explícita de rutas; nunca recorre carpetas de juegos."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
from . import paths, setup
from .store import load_json, write_json_atomic

PACKAGE = 'omnia-desktop-suite-installer'
APPLETS = ['org.omnia.desktop', 'org.omnia.header', 'org.omnia.hero', 'org.omnia.activity', 'org.omnia.system', 'org.omnia.carousel']


def owned_paths(home=None):
    home = Path(home or Path.home())
    config = paths.config_dir() if home == Path.home() else home/'.config/omnia'
    data = home/'.local/share'
    cache = paths.cache_dir() if home == Path.home() else home/'.cache/omnia'
    result = [config, cache, home/'.local/lib/omnia', home/'.local/lib/qt6/qml/org/omnia/session']
    result += [data/'omnia'/name for name in ('art','ui','kwin','assets','installer','empty-desktop','omnia-layout.js')]
    result += [data/'plasma/plasmoids'/name for name in APPLETS]
    result += [data/'plasma/wallpapers/org.omnia.launcher']
    result += [data/'kwin/scripts'/name for name in ('omnia-showdesktop','omnia-watch')]
    result += [home/'.local/bin'/name for name in ('omnia-core','omnia-ui','omnia-setup','omnia-first-run','omnia-layout','omnia-settings','omnia-uninstall')]
    result += [home/'.config/systemd/user'/name for name in ('omnia.service','omnia-ui.service')]
    result += [home/'.config/plasma-workspace/env/omnia.sh',home/'.config/environment.d/60-omnia-qml.conf']
    result += [data/'applications'/name for name in ('org.omnia.settings.desktop','org.omnia.uninstall.desktop')]
    result += [data/'icons/hicolor/scalable/apps/org.omnia.menu.svg',home/'.config/autostart/omnia-first-run.desktop']
    if home == Path.home() and paths.data_dir() != data/'omnia': result.append(paths.data_dir()/'art')
    return list(dict.fromkeys(result))


def validate_paths(items, config):
    """Rechaza redirecciones de los padres y cualquier solapamiento con juegos/partidas registrados."""
    protected = []
    library = load_json(Path(config)/'library.json', {})
    cfg=load_json(Path(config)/'config.json',{})
    state=load_json(Path(config)/'state.json',{})
    overrides=list((state.get('saves') or {}).values())
    backup=(cfg.get('saves') or {}).get('backup_root')
    if isinstance(backup,str) and backup: protected.append(Path(os.path.expanduser(backup)).absolute())
    for value in overrides:
        if not isinstance(value,dict): continue
        backup=value.get('backup_dir')
        if isinstance(backup,str) and backup: protected.append(Path(os.path.expanduser(backup)).absolute())
        spec=value.get('spec') or {}
        for entry in spec.get('files',[])+spec.get('dirs',[])+([spec['glob']] if isinstance(spec.get('glob'),str) else []):
            if isinstance(entry,str): protected.append(Path(os.path.expanduser(entry.split('*')[0])).absolute())
    for game in library.get('games', []):
        for port in game.get('ports', []):
            for value in [port.get('check'),port.get('backup_dir')]:
                if isinstance(value,str) and value: protected.append(Path(os.path.expanduser(value)).absolute())
            saves=port.get('saves') or {}
            for value in saves.get('files',[]) + saves.get('dirs',[]) + ([saves['glob']] if isinstance(saves.get('glob'),str) else []):
                if isinstance(value,str): protected.append(Path(os.path.expanduser(value.split('*')[0])).absolute())
    for item in items:
        item=Path(item).absolute()
        if item.is_symlink(): continue  # se elimina solo el enlace, nunca su destino
        if any(parent.is_symlink() for parent in item.parents):
            raise ValueError('Ruta redirigida mediante enlace; se conserva: '+str(item))
        if any(p == item or item in p.parents for p in protected):
            raise ValueError('Esta ruta contiene juegos o partidas registrados y se conserva: '+str(item))


def remove_paths(items):
    for item in items:
        item=Path(item)
        if item.is_symlink() or item.is_file(): item.unlink()
        elif item.is_dir(): shutil.rmtree(item)


def qdbus(script):
    binary=shutil.which('qdbus6') or shutil.which('qdbus')
    if not binary: raise RuntimeError('No se encontró qdbus para retirar Omnia del escritorio.')
    result=subprocess.run([binary,'org.kde.plasmashell','/PlasmaShell','org.kde.PlasmaShell.evaluateScript',script],capture_output=True,text=True,timeout=30)
    if result.returncode: raise RuntimeError('No se pudo actualizar Plasma. No se borraron los archivos de Omnia.')
    return result.stdout.strip()


def capture_desktop():
    file=paths.config_dir()/'desktop-before-omnia.json'
    previous=load_json(file,{})
    current=json.loads(qdbus('var rows=[];var ds=desktops();for(var i=0;i<ds.length;i++){var d=ds[i];d.currentConfigGroup=["General"];rows.push({id:String(d.id),wallpaper:d.wallpaperPlugin,url:d.readConfig("url","")});}print(JSON.stringify(rows));'))
    for row in current:
        if row['id'] not in previous and row['wallpaper'] != 'org.omnia.launcher': previous[row['id']]=row
    if previous: write_json_atomic(file,previous)


def detach_script(previous, desktop_url):
    prefix = 'var previous='+json.dumps(previous)+';var ids='+json.dumps(APPLETS)+';var desktopUrl='+json.dumps(desktop_url)+';'
    return prefix + '''var ds=desktops();
for(var i=0;i<ds.length;i++){
 var d=ds[i], widgets=d.widgets();
 for(var j=widgets.length-1;j>=0;j--)if(ids.indexOf(widgets[j].type)>=0)widgets[j].remove();
 var old=previous[String(d.id)];
 if(d.wallpaperPlugin=="org.omnia.launcher")d.wallpaperPlugin=old&&old.wallpaper&&old.wallpaper!="org.omnia.launcher"?old.wallpaper:"org.kde.image";
 d.currentConfigGroup=["General"];
 var url=d.readConfig("url","");
 if(String(url).indexOf("/omnia/empty-desktop")>=0)d.writeConfig("url",old&&old.url?old.url:desktopUrl);
}print("Omnia retirado de los escritorios");'''


def plan():
    package=False
    if shutil.which('pacman'):
        package=subprocess.run(['pacman','-Q',PACKAGE],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
    return {'paths':[str(p) for p in owned_paths() if p.exists() or p.is_symlink()], 'package_installed':package}


def uninstall(remove_package=False):
    if os.geteuid()==0: raise ValueError('Abre el desinstalador como usuario normal, sin sudo.')
    if Path('/usr/lib/systemd/user/omnia.service').exists():
        raise RuntimeError('Esta instalación incluye paquetes de Omnia del sistema (omnia-core/omnia-ui/omnia-kde). Retíralos desde el gestor de paquetes antes de borrar los datos de usuario.')
    items=owned_paths();validate_paths(items,paths.config_dir())
    # Deshace atajos antes de borrar el respaldo; si falla, no retira los archivos.
    backend=setup.KdeBackend()
    if (paths.config_dir()/setup.BACKUP_NAME).exists(): setup.undo(backend,paths.config_dir())
    for script in setup.SCRIPTS:
        if backend.plugin_enabled(script): backend.set_plugin_enabled(script,False)
    backend.reload_kwin()
    previous=load_json(paths.config_dir()/'desktop-before-omnia.json',{})
    desktop=next((p for p in (Path.home()/'Escritorio',Path.home()/'Desktop') if p.is_dir()),Path.home())
    qdbus(detach_script(previous,desktop.as_uri()))
    for service in ('omnia.service','omnia-ui.service'):
        subprocess.run(['systemctl','--user','disable','--now',service],capture_output=True,text=True,timeout=30)
        status=subprocess.run(['systemctl','--user','is-active','--quiet',service],timeout=10)
        if status.returncode==0: raise RuntimeError('No se pudo detener '+service+'. Se conservaron los archivos.')
    # Recupera descargas suspendidas si el servicio había fallado antes de cerrarse.
    from .gamemode import Freezer
    Freezer(paths.cache_dir()/'gamemode.json').resume()
    result=subprocess.run(['systemctl','--user','show-environment'],capture_output=True,text=True,check=True)
    current=next((line.split('=',1)[1] for line in result.stdout.splitlines() if line.startswith('QML_IMPORT_PATH=')),'')
    qml=Path.home()/'.local/lib/qt6/qml'
    other_plugins=any(qml/'org/omnia/session' not in file.parents for file in qml.rglob('qmldir'))
    imports=[p for p in current.split(':') if p and (p!=str(qml) or other_plugins)]
    if imports: subprocess.run(['systemctl','--user','set-environment','QML_IMPORT_PATH='+':'.join(imports)],check=True)
    else: subprocess.run(['systemctl','--user','unset-environment','QML_IMPORT_PATH'],check=True)
    remove_paths(items)
    runtime=paths.runtime_dir()
    if runtime.is_dir() and not runtime.is_symlink():
        for name in ('token',): (runtime/name).unlink(missing_ok=True)
        try: runtime.rmdir()
        except OSError: pass
    data=Path.home()/'.local/share/omnia'
    try: data.rmdir()
    except OSError: pass  # conserva cualquier archivo ajeno a la lista del instalador
    subprocess.run(['systemctl','--user','daemon-reload'],check=True)
    subprocess.run(['systemctl','--user','restart','plasma-plasmashell.service'],check=True)
    if shutil.which('kbuildsycoca6'): subprocess.run(['kbuildsycoca6','--noincremental'],capture_output=True)
    if remove_package and plan()['package_installed']:
        result=subprocess.run(['pkexec','/usr/bin/pacman','-R','--noconfirm',PACKAGE],capture_output=True,text=True)
        if result.returncode: return 'Omnia se retiró de tu usuario. El asistente del sistema sigue instalado; puedes retirarlo desde el gestor de paquetes.'
    return 'Omnia y sus datos de usuario se retiraron. Tus juegos, emuladores, partidas y respaldos se conservaron.'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture-desktop',action='store_true')
    args=parser.parse_args()
    if args.capture_desktop: capture_desktop()


if __name__=='__main__': main()
