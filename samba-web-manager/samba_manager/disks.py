#!/usr/bin/env python3
"""
Модуль для обнаружения и управления дисками
"""

import os
import subprocess
import re
import json
from typing import List, Dict, Optional
from dataclasses import dataclass, asdict
import datetime


@dataclass
class DiskInfo:
    device: str
    mount_point: Optional[str]
    size: int
    size_human: str
    used: int
    used_human: str
    free: int
    free_human: str
    usage_percent: int
    filesystem: str
    label: str
    uuid: str
    is_mounted: bool
    is_auto_mount: bool
    model: str
    vendor: str
    serial: str
    type: str
    partition_table: str


@dataclass
class MountOptions:
    mount_point: str
    filesystem: Optional[str] = None
    options: List[str] = None
    fstab: bool = False
    auto_mount: bool = True


class DiskManager:
    def __init__(self):
        self.mount_base = '/mnt'
        self.udev_rules_dir = '/etc/udev/rules.d'

    def detect_disks(self) -> List[DiskInfo]:
        disks = []
        lsblk_output = self._get_lsblk_output()
        if lsblk_output:
            disks.extend(self._parse_lsblk(lsblk_output))
        return disks

    def _get_lsblk_output(self) -> str:
        try:
            # LC_ALL=C — чтобы размеры были в формате "3.6T", не "3,6T"
            env = os.environ.copy()
            env['LC_ALL'] = 'C'
            env['LANG'] = 'C'

            result = subprocess.run(
                ['lsblk', '-J', '-b',
                 '-o', 'NAME,SIZE,TYPE,MOUNTPOINT,LABEL,UUID,FSTYPE,MODEL,VENDOR,SERIAL'],
                capture_output=True, text=True, check=True, env=env,
            )
            return result.stdout
        except Exception:
            return ''

    def _parse_lsblk(self, output: str) -> List[DiskInfo]:
        disks = []
        try:
            data = json.loads(output)
            for device in data.get('blockdevices', []):
                self._parse_device(device, disks)
        except Exception:
            pass
        return disks

    def _parse_device(self, device: Dict, disks: List[DiskInfo], prefix: str = ''):
        name = device.get('name', '')
        if not name:
            return

        if 'children' in device:
            for child in device['children']:
                self._parse_device(child, disks, prefix)
            return

        if device.get('type') != 'part':
            return

        full_name = f"{prefix}{name}" if prefix else name
        mount_point = device.get('mountpoint')
        is_mounted = bool(mount_point)
        disk_type = self._detect_disk_type(full_name)

        # --- Размеры: теперь lsblk -b возвращает БАЙТЫ (int), не строку ---
        size = self._safe_int(device.get('size', 0))

        # --- Занято/свободно — через df (байты) ---
        used = 0
        free = size
        usage_percent = 0

        if is_mounted and mount_point:
            usage = self._get_mount_usage(mount_point)
            used = usage.get('used', 0)
            free = usage.get('free', 0)
            usage_percent = usage.get('percent', 0)
            # Если df вернул total — перезапишем size (точнее для NTFS/exFAT)
            if usage.get('total', 0) > 0:
                size = usage['total']

        disk_info = DiskInfo(
            device=f"/dev/{full_name}",
            mount_point=mount_point,
            size=size,
            size_human=self._format_size(size),
            used=used,
            used_human=self._format_size(used),
            free=free,
            free_human=self._format_size(free),
            usage_percent=usage_percent,
            filesystem=device.get('fstype') or 'unknown',
            label=device.get('label') or '',
            uuid=device.get('uuid') or '',
            is_mounted=is_mounted,
            is_auto_mount=False,
            model=device.get('model') or 'Unknown',
            vendor=device.get('vendor') or 'Unknown',
            serial=device.get('serial') or '',
            type=disk_type,
            partition_table=device.get('pttype') or 'unknown',
        )
        disks.append(disk_info)
        return disks

    def _safe_int(self, value) -> int:
        """Безопасно преобразует значение в int (учитывает '3,6T', '3.6T', '12345')."""
        if isinstance(value, int):
            return value
        if not value:
            return 0
        s = str(value).strip().upper()

        # Если уже число — вернём как есть
        try:
            return int(s)
        except ValueError:
            pass

        # Иначе — парсим "3.6T" / "3,6T" / "1.5M" и т.д.
        # Заменяем запятую на точку (русская локаль)
        s = s.replace(',', '.')

        multipliers = {
            'B': 1,
            'K': 1024,
            'KB': 1024,
            'M': 1024 ** 2,
            'MB': 1024 ** 2,
            'G': 1024 ** 3,
            'GB': 1024 ** 3,
            'T': 1024 ** 4,
            'TB': 1024 ** 4,
            'P': 1024 ** 5,
            'PB': 1024 ** 5,
        }
        # Сортируем по длине суффикса (сначала "KB", потом "K")
        for suffix in sorted(multipliers.keys(), key=len, reverse=True):
            if s.endswith(suffix):
                num_str = s[:-len(suffix)].strip()
                try:
                    num = float(num_str)
                    return int(num * multipliers[suffix])
                except ValueError:
                    return 0
        return 0

    def _detect_disk_type(self, device_name: str) -> str:
        if device_name.startswith('nvme'):
            return 'NVMe'
        elif device_name.startswith('sd'):
            return 'SATA'
        elif device_name.startswith('vd'):
            return 'Virtual'
        elif device_name.startswith('mmcblk'):
            return 'MMC'
        else:
            return 'USB'

    def _get_mount_usage(self, mount_point: str) -> Dict:
        """Возвращает used/free/total в байтах через df -B1."""
        try:
            env = os.environ.copy()
            env['LC_ALL'] = 'C'
            env['LANG'] = 'C'

            result = subprocess.run(
                ['df', '-B1', mount_point],
                capture_output=True, text=True, check=True, env=env,
            )
            lines = result.stdout.strip().split('\n')
            if len(lines) >= 2:
                parts = lines[1].split()
                if len(parts) >= 5:
                    return {
                        'total': int(parts[1]),
                        'used': int(parts[2]),
                        'free': int(parts[3]),
                        'percent': int(parts[4].replace('%', '')),
                    }
        except Exception:
            pass
        return {'total': 0, 'used': 0, 'free': 0, 'percent': 0}

    def _format_size(self, size: int) -> str:
        try:
            size = float(size)
        except (TypeError, ValueError):
            return '0 B'
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size < 1024.0:
                return f"{size:.1f} {unit}"
            size /= 1024.0
        return f"{size:.1f} PB"

    def mount_disk(self, device: str, options: MountOptions) -> bool:
        try:
            mount_point = options.mount_point
            if not os.path.exists(mount_point):
                os.makedirs(mount_point, exist_ok=True)

            cmd = ['sudo', 'mount']
            if options.filesystem:
                cmd.extend(['-t', options.filesystem])
            if options.options:
                cmd.extend(['-o', ','.join(options.options)])
            cmd.extend([device, mount_point])

            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                raise Exception(result.stderr)

            if options.fstab:
                self._add_to_fstab(
                    device, mount_point,
                    options.filesystem or 'auto',
                    options.options or [],
                )

            self._set_ownership(mount_point)
            return True
        except Exception as e:
            print(f"Ошибка монтирования {device}: {e}")
            return False

    def unmount_disk(self, mount_point: str, remove_fstab: bool = False) -> bool:
        try:
            if not os.path.ismount(mount_point):
                return True

            result = subprocess.run(
                ['sudo', 'umount', mount_point],
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                result = subprocess.run(
                    ['sudo', 'umount', '-l', mount_point],
                    capture_output=True, text=True,
                )
                if result.returncode != 0:
                    raise Exception(result.stderr)

            if remove_fstab:
                self._remove_from_fstab(mount_point)
            return True
        except Exception as e:
            print(f"Ошибка отмонтирования {mount_point}: {e}")
            return False

    def _add_to_fstab(self, device: str, mount_point: str,
                      fs_type: str, options: List[str]):
        try:
            with open('/etc/fstab', 'r') as f:
                if mount_point in f.read():
                    return

            options_str = ','.join(options) if options else 'defaults'
            entry = f"{device} {mount_point} {fs_type} {options_str} 0 2\n"
            with open('/etc/fstab', 'a') as f:
                f.write(entry)
        except Exception:
            pass

    def _remove_from_fstab(self, mount_point: str):
        try:
            with open('/etc/fstab', 'r') as f:
                lines = f.readlines()
            with open('/etc/fstab', 'w') as f:
                for line in lines:
                    if mount_point not in line:
                        f.write(line)
        except Exception:
            pass

    def _set_ownership(self, mount_point: str):
        try:
            subprocess.run(
                ['sudo', 'useradd', '-r', '-s', '/bin/false', 'samba-user'],
                stderr=subprocess.DEVNULL,
            )
            subprocess.run(
                ['sudo', 'chown', '-R', 'samba-user:users', mount_point],
            )
            subprocess.run(['sudo', 'chmod', '2775', mount_point])
        except Exception:
            pass

    def get_available_mount_points(self) -> List[str]:
        mount_points = []
        if not os.path.exists(self.mount_base):
            return mount_points
        for item in os.listdir(self.mount_base):
            path = os.path.join(self.mount_base, item)
            if os.path.isdir(path) and not os.path.ismount(path):
                mount_points.append(path)
        return mount_points

    def create_mount_point(self, name: str) -> str:
        path = os.path.join(self.mount_base, name)
        if not os.path.exists(path):
            os.makedirs(path, exist_ok=True)
        return path

    def auto_mount_detected_disks(self):
        disks = self.detect_disks()
        for disk in disks:
            if not disk.is_mounted and disk.type in ['USB', 'SATA']:
                label = disk.label or f"disk_{disk.device.split('/')[-1]}"
                mount_point = os.path.join(self.mount_base, label)
                options = MountOptions(
                    mount_point=mount_point,
                    filesystem=disk.filesystem if disk.filesystem != 'unknown' else None,
                    options=['rw', 'noatime'],
                    fstab=True,
                    auto_mount=True,
                )
                self.mount_disk(disk.device, options)


class DiskAPI:
    def __init__(self):
        self.manager = DiskManager()

    def get_disk_status(self) -> Dict:
        disks = self.manager.detect_disks()
        return {
            'disks': [asdict(d) for d in disks],
            'total_disks': len(disks),
            'mounted_disks': sum(1 for d in disks if d.is_mounted),
            'available_mount_points': self.manager.get_available_mount_points(),
        }

    def mount_disk_api(self, device: str, mount_point: str, options: Dict) -> Dict:
        try:
            mount_options = MountOptions(
                mount_point=mount_point,
                filesystem=options.get('filesystem'),
                options=options.get('options', ['rw', 'noatime']),
                fstab=options.get('fstab', False),
                auto_mount=options.get('auto_mount', True),
            )
            success = self.manager.mount_disk(device, mount_options)
            return {
                'success': success,
                'message': (
                    f'Диск {device} смонтирован' if success
                    else 'Ошибка монтирования'
                ),
            }
        except Exception as e:
            return {'success': False, 'error': str(e)}

    def unmount_disk_api(self, mount_point: str, remove_fstab: bool = False) -> Dict:
        try:
            success = self.manager.unmount_disk(mount_point, remove_fstab)
            return {
                'success': success,
                'message': (
                    f'Диск {mount_point} отмонтирован' if success
                    else 'Ошибка отмонтирования'
                ),
            }
        except Exception as e:
            return {'success': False, 'error': str(e)}