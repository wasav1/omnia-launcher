#!/usr/bin/env python3
"""Crea la configuración privada de MangoHud con los nombres reales del equipo."""
import os
from pathlib import Path
import re
import subprocess
import sys


def cpu_name():
    try:
        for line in Path('/proc/cpuinfo').read_text(errors='replace').splitlines():
            if line.lower().startswith('model name'):
                value = line.split(':', 1)[1].strip()
                value = re.sub(r'\s+@\s+.*$', '', value)
                value = value.replace('(R)', '').replace('(TM)', '').strip()
                value = re.sub(r'\s+CPU\s*$', '', value, flags=re.I)
                return re.sub(r'\s+', ' ', value)
    except OSError:
        pass
    return ''


def gpu_devices():
    try:
        output = subprocess.check_output(['lspci', '-Dnn'], text=True, stderr=subprocess.DEVNULL, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return []
    devices = []
    for line in output.splitlines():
        if not re.search(r'\b(VGA compatible controller|3D controller|Display controller)\b', line, re.I):
            continue
        match = re.match(r'^(\S+)\s+', line)
        if not match:
            continue
        pci = match.group(1)
        # El nombre entre corchetes suele ser el modelo comercial (p. ej. GeForce RTX 3050 Mobile).
        bracketed = re.findall(r'\[([^\]]+)\]', line)
        name = next((x for x in reversed(bracketed) if re.search(
            r'(GeForce|RTX|GTX|Radeon|Arc|Iris|UHD|Graphics|RX\s*\d)', x, re.I)), '')
        if not name:
            name = line.split(': ', 1)[-1]
            name = re.sub(r'\s*\(rev .*$', '', name).strip()
            name = re.sub(r'^(Intel|NVIDIA|Advanced Micro Devices,? Inc\.?|AMD)\s+', '', name, flags=re.I)
        name = re.sub(r'\s+', ' ', name.strip())
        if not name:
            continue
        # GPU dedicada sobre integrada; la memoria dedicada desempata entre
        # varias tarjetas. MangoHud acepta el PCI BDF directamente, así que
        # no dependemos del orden distinto de lspci, DRM o Vulkan.
        integrated = bool(re.search(r'(uhd|iris|radeon graphics)', name, re.I))
        memory = 0
        vram_path = Path('/sys/bus/pci/devices') / pci / 'mem_info_vram_total'
        try:
            memory = int(vram_path.read_text().strip())
        except (OSError, ValueError):
            pass
        devices.append({
            'pci': pci,
            'name': name,
            'dedicated': not integrated,
            'memory': memory,
        })
    return devices


def strongest_gpu(devices):
    if not devices:
        return None
    # En el caso común Intel integrada + NVIDIA/AMD dedicada, siempre gana la
    # dedicada. La VRAM física desempata cuando el sistema expone ese dato.
    return max(devices, key=lambda gpu: (gpu['dedicated'], gpu['memory']))


def update_line(lines, key, value, fallback):
    indexes = [i for i, line in enumerate(lines) if line.startswith(key + '=')]
    if value:
        replacement = key + '=' + value
        if indexes:
            current = lines[indexes[0]].split('=', 1)[1].strip()
            if current == fallback or not current:
                lines[indexes[0]] = replacement
        else:
            lines.append(replacement)
    elif indexes:
        # Conserva una etiqueta personalizada; solo retira el valor fijo de la plantilla.
        for i in reversed(indexes):
            if not lines[i].split('=', 1)[1].strip() or lines[i].split('=', 1)[1].strip() == fallback:
                lines.pop(i)


def main():
    if len(sys.argv) != 3:
        raise SystemExit('Uso: mangohud_config.py PLANTILLA CONFIGURACIÓN')
    template, target = map(Path, sys.argv[1:])
    target.parent.mkdir(parents=True, exist_ok=True)
    cpu = cpu_name()
    gpus = gpu_devices()
    selected_gpu = strongest_gpu(gpus)
    source = target.read_text(errors='replace') if target.is_file() else template.read_text(errors='replace')
    lines = source.splitlines()

    font = Path.home() / '.local/share/fonts/MarcellusSC.ttf'
    font_lines = [i for i, line in enumerate(lines) if line.startswith('font_file=')]
    if font.is_file():
        if font_lines:
            lines[font_lines[0]] = 'font_file=' + str(font)
        else:
            lines.append('font_file=' + str(font))
    else:
        for i in reversed(font_lines):
            lines.pop(i)

    update_line(lines, 'cpu_text', cpu, 'i5-10300H')
    if selected_gpu:
        # Estas dos opciones son automáticas en la configuración de Omnia:
        # pci_dev evita que MangoHud seleccione la iGPU por orden de enumeración.
        for key, value in (('pci_dev', selected_gpu['pci']), ('gpu_text', selected_gpu['name'])):
            indexes = [i for i, line in enumerate(lines) if line.startswith(key + '=')]
            replacement = f'{key}={value}'
            if indexes:
                lines[indexes[0]] = replacement
                for i in reversed(indexes[1:]):
                    lines.pop(i)
            else:
                lines.append(replacement)
        # gpu_list es una selección por índice y puede contradecir pci_dev.
        lines = [line for line in lines if not line.startswith('gpu_list=')]
    target.write_text('\n'.join(lines).rstrip() + '\n')
    os.chmod(target, 0o600)


if __name__ == '__main__':
    main()
