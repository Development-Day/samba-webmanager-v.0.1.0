#!/usr/bin/env python3
"""
Веб-установщик Samba Web Manager.

Запускается отдельно, не требует предварительной установки Flask —
если Flask не найден, устанавливает его автоматически через apt/pip.

Использование:
    sudo python3 installer_app.py

Затем откройте в браузере: http://<IP-сервера>:5001
"""

import os
import sys
import time
import shutil
import secrets
import socket
import platform
import subprocess


# ============================================================
# BOOTSTRAP: проверка и автоустановка Flask
# ============================================================

def _ensure_flask() -> bool:
    """Проверяет наличие Flask. Если нет — ставит через apt или pip."""
    try:
        import flask  # noqa: F401
        return True
    except ImportError:
        pass

    print("⚠️  Flask не найден. Устанавливаю...")
    print("   Это может занять 1–2 минуты.\n", flush=True)

    # --- Способ 1: apt (предпочтительно на Debian/Ubuntu) ---
    if shutil.which('apt-get'):
        try:
            subprocess.run(['apt-get', 'update', '-qq'], check=False)
            result = subprocess.run(
                ['apt-get', 'install', '-y', '-qq',
                 'python3-flask', 'python3-pip', 'python3-venv'],
                check=False,
            )
            if result.returncode == 0:
                try:
                    import flask  # noqa: F401
                    print("\n✅ Flask установлен через apt.\n", flush=True)
                    return True
                except ImportError:
                    pass
        except Exception as e:
            print(f"⚠️  apt-установка не удалась: {e}", flush=True)

    # --- Способ 2: python3 -m pip ---
    try:
        result = subprocess.run(
            [sys.executable, '-m', 'pip', 'install',
             '--break-system-packages', 'Flask'],
            check=False,
        )
        if result.returncode == 0:
            try:
                import flask  # noqa: F401
                print("\n✅ Flask установлен через pip.\n", flush=True)
                return True
            except ImportError:
                pass
    except Exception:
        pass

    # --- Способ 3: pip3 / pip ---
    for pip_cmd in ('pip3', 'pip'):
        if shutil.which(pip_cmd):
            try:
                result = subprocess.run(
                    [pip_cmd, 'install', '--break-system-packages', 'Flask'],
                    check=False,
                )
                if result.returncode == 0:
                    try:
                        import flask  # noqa: F401
                        print(f"\n✅ Flask установлен через {pip_cmd}.\n", flush=True)
                        return True
                    except ImportError:
                        pass
            except Exception:
                pass

    print("\n❌ Не удалось установить Flask автоматически.", flush=True)
    print("   Установите вручную:", flush=True)
    print("     sudo apt install python3-flask python3-pip", flush=True)
    print("   или:", flush=True)
    print("     sudo pip3 install --break-system-packages Flask", flush=True)
    return False


if not _ensure_flask():
    sys.exit(1)


# ============================================================
# Flask импортируется только после bootstrap
# ============================================================

from flask import (
    Flask, send_from_directory, request, jsonify,
)


# ============================================================
# Приложение
# ============================================================

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATES_DIR = os.path.join(BASE_DIR, 'templates')

app = Flask(__name__, template_folder=TEMPLATES_DIR)
app.secret_key = secrets.token_hex(32)

APP_DIR = '/opt/samba-web-manager'


# ============================================================
# ХЕЛПЕРЫ: пакеты и сервисы
# ============================================================

def _pkg_installed(pkg: str) -> bool:
    """Быстрая проверка одного пакета через dpkg-query."""
    try:
        proc = subprocess.run(
            ['dpkg-query', '-W', '-f=${Status}', pkg],
            capture_output=True, text=True, check=False, timeout=3,
        )
        return 'install ok installed' in proc.stdout
    except Exception:
        return False


def _pkg_version(pkg: str) -> str:
    """Версия установленного пакета."""
    try:
        proc = subprocess.run(
            ['dpkg-query', '-W', '-f=${Version}', pkg],
            capture_output=True, text=True, check=False, timeout=3,
        )
        return proc.stdout.strip() or 'unknown'
    except Exception:
        return 'unknown'


def _service_active(name: str) -> bool:
    """Активен ли systemd-юнит."""
    try:
        proc = subprocess.run(
            ['systemctl', 'is-active', name],
            capture_output=True, text=True, check=False, timeout=3,
        )
        return proc.stdout.strip() == 'active'
    except Exception:
        return False


def _samba_user_exists(username: str) -> bool:
    """Есть ли Samba-пользователь (через pdbedit)."""
    try:
        proc = subprocess.run(
            ['pdbedit', '-L'],
            capture_output=True, text=True, check=False, timeout=5,
        )
        for line in proc.stdout.splitlines():
            if ':' in line and line.split(':', 1)[0] == username:
                return True
    except Exception:
        pass
    return False


# ============================================================
# ПРОВЕРКИ СИСТЕМЫ
# ============================================================

def check_root() -> dict:
    ok = os.geteuid() == 0
    return {
        'status': ok,
        'message': 'Права root получены' if ok else 'Запустите с sudo!',
    }


def check_os() -> dict:
    os_name = platform.system()
    is_debian = os.path.exists('/etc/debian_version')
    version = 'unknown'
    if is_debian:
        try:
            with open('/etc/debian_version') as f:
                version = f.read().strip()
        except Exception:
            pass
    return {
        'status': is_debian,
        'os': os_name,
        'version': version,
        'message': (
            f'Debian/Ubuntu {version}' if is_debian
            else f'{os_name} не поддерживается'
        ),
    }


def check_internet() -> dict:
    for host in (('1.1.1.1', 53), ('8.8.8.8', 53)):
        try:
            socket.create_connection(host, timeout=2)
            return {'status': True, 'message': 'Интернет доступен'}
        except OSError:
            continue
    return {'status': False, 'message': 'Нет подключения к интернету'}


def check_packages() -> dict:
    """Детальная проверка пакетов и сервисов (быстро, одним вызовом)."""
    packages_list = (
        'samba', 'smbclient', 'cifs-utils',
        'python3', 'python3-pip', 'python3-venv',
        'acl', 'rsync',
    )

    installed_map = {p: False for p in packages_list}
    try:
        proc = subprocess.run(
            ['dpkg-query', '-W', '-f=${Package}\t${Status}\n']
            + list(packages_list),
            capture_output=True, text=True, check=False, timeout=5,
        )
        for line in proc.stdout.splitlines():
            if '\t' not in line:
                continue
            name, status = line.split('\t', 1)
            if 'install ok installed' in status:
                installed_map[name] = True
    except Exception:
        pass

    result = {}
    for pkg in packages_list:
        result[pkg] = {
            'installed': installed_map[pkg],
            'version': _pkg_version(pkg) if installed_map[pkg] else None,
        }

    # Служебные флаги
    result['smbd_active'] = {'installed': _service_active('smbd')}
    result['nmbd_active'] = {'installed': _service_active('nmbd')}
    result['app_installed'] = {
        'installed': os.path.exists(os.path.join(APP_DIR, 'app.py'))
    }
    result['venv_installed'] = {
        'installed': os.path.exists(
            os.path.join(APP_DIR, 'venv', 'bin', 'python')
        )
    }
    result['env_installed'] = {
        'installed': os.path.exists(os.path.join(APP_DIR, '.env'))
    }
    result['app_service'] = {'installed': _service_active('samba-web')}

    return result


def check_python_version() -> dict:
    v = sys.version_info
    return {
        'version': f'{v.major}.{v.minor}.{v.micro}',
        'status': v.major == 3 and v.minor >= 8,
        'message': f'Python {v.major}.{v.minor} (требуется 3.8+)',
    }


def check_port(port: int = 5000) -> dict:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(('0.0.0.0', port))
        free = True
    except OSError:
        free = False
    finally:
        sock.close()
    return {
        'status': free,
        'port': port,
        'message': f'Порт {port} свободен' if free else f'Порт {port} занят',
    }


def get_system_info() -> dict:
    pkgs = check_packages()
    pkgs_simple = {
        name: data['installed'] if isinstance(data, dict) else data
        for name, data in pkgs.items()
    }
    return {
        'root': check_root(),
        'os': check_os(),
        'internet': check_internet(),
        'packages': pkgs_simple,
        'packages_detailed': pkgs,
        'python': check_python_version(),
        'port': check_port(5000),
        'hostname': socket.gethostname(),
        'kernel': platform.release(),
    }


# ============================================================
# УСТАНОВКА КОМПОНЕНТОВ
# ============================================================

def install_package(package: str) -> tuple:
    try:
        env = os.environ.copy()
        env['DEBIAN_FRONTEND'] = 'noninteractive'
        result = subprocess.run(
            ['apt-get', 'install', '-y', '-qq', package],
            capture_output=True, text=True, check=False, env=env,
        )
        output = (result.stdout + result.stderr)[-300:]
        return result.returncode == 0, output
    except Exception as e:
        return False, str(e)


def setup_samba_share(name, path, read_only=False, guest_ok=True) -> bool:
    block = f"""
[{name}]
   path = {path}
   read only = {'yes' if read_only else 'no'}
   guest ok = {'yes' if guest_ok else 'no'}
   browseable = yes
   create mask = 0755
   directory mask = 0755
"""
    try:
        with open('/etc/samba/smb.conf', 'a', encoding='utf-8') as f:
            f.write(block)
        return True
    except Exception:
        return False


def create_samba_user(username: str, password: str) -> bool:
    try:
        subprocess.run(
            ['useradd', '-M', '-s', '/usr/sbin/nologin', username],
            capture_output=True, check=False,
        )
        proc = subprocess.run(
            ['smbpasswd', '-a', '-s', username],
            input=f'{password}\n{password}\n'.encode(),
            capture_output=True,
        )
        return proc.returncode == 0
    except Exception:
        return False


def restart_samba() -> bool:
    try:
        subprocess.run(['systemctl', 'restart', 'smbd'],
                       capture_output=True, check=False)
        subprocess.run(['systemctl', 'restart', 'nmbd'],
                       capture_output=True, check=False)
        return True
    except Exception:
        return False


# ============================================================
# ПОИСК И КОПИРОВАНИЕ ПРИЛОЖЕНИЯ
# ============================================================

def find_app_source() -> str:
    candidates = [
        os.path.join(BASE_DIR, 'samba-web-manager'),
        os.path.join(BASE_DIR, '..', 'samba-web-manager'),
        os.path.join(BASE_DIR, 'app'),
    ]
    for path in candidates:
        path = os.path.abspath(path)
        if os.path.exists(os.path.join(path, 'app.py')):
            return path
    return None


def install_app_files() -> tuple:
    source = find_app_source()
    if not source:
        return False, (
            'Не найдена папка samba-web-manager/ рядом с установщиком.'
        )

    os.makedirs(APP_DIR, exist_ok=True)

    keep = {'.env', 'venv', 'logs', 'backups'}
    for item in os.listdir(APP_DIR):
        if item in keep:
            continue
        full = os.path.join(APP_DIR, item)
        if os.path.isdir(full):
            shutil.rmtree(full, ignore_errors=True)
        else:
            try:
                os.remove(full)
            except Exception:
                pass

    for item in os.listdir(source):
        if item in ('venv', '.venv', '.env', '__pycache__',
                    '.git', 'logs', 'backups'):
            continue
        src = os.path.join(source, item)
        dst = os.path.join(APP_DIR, item)
        if os.path.isdir(src):
            shutil.copytree(
                src, dst, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('__pycache__', '*.pyc'),
            )
        else:
            shutil.copy2(src, dst)

    return True, f'Файлы скопированы из {source}'


def create_venv_and_install() -> tuple:
    venv_dir = os.path.join(APP_DIR, 'venv')
    if not os.path.exists(os.path.join(venv_dir, 'bin', 'python')):
        proc = subprocess.run(
            ['python3', '-m', 'venv', venv_dir],
            capture_output=True, text=True, check=False,
        )
        if proc.returncode != 0:
            return False, f'venv: {proc.stderr[-300:]}'

    pip = os.path.join(venv_dir, 'bin', 'pip')
    req = os.path.join(APP_DIR, 'requirements.txt')

    subprocess.run([pip, 'install', '-q', '--upgrade', 'pip'],
                   capture_output=True, check=False)

    if os.path.exists(req):
        proc = subprocess.run(
            [pip, 'install', '-q', '-r', req],
            capture_output=True, text=True, check=False,
        )
        if proc.returncode != 0:
            return False, f'pip install: {proc.stderr[-300:]}'

    return True, 'Зависимости установлены'


def create_env_file(admin_user: str, admin_pass: str) -> str:
    env_path = os.path.join(APP_DIR, '.env')
    secret_key = secrets.token_hex(32)

    content = f"""# Samba Web Manager - Конфигурация
SECRET_KEY={secret_key}
FLASK_ENV=production
PORT=5000

ADMIN_USERNAME={admin_user}
ADMIN_PASSWORD={admin_pass}

SAMBA_CONFIG=/etc/samba/smb.conf
SAMBA_PASSWD=/etc/samba/smbpasswd
WORKGROUP=WORKGROUP

ALLOWED_HOSTS=*
SESSION_COOKIE_SECURE=False
LOG_LEVEL=INFO
"""
    os.makedirs(APP_DIR, exist_ok=True)
    with open(env_path, 'w', encoding='utf-8') as f:
        f.write(content)
    os.chmod(env_path, 0o600)
    return env_path


def create_systemd_service() -> tuple:
    service_content = f"""[Unit]
Description=Samba Web Manager
After=network.target smbd.service nmbd.service
Wants=smbd.service

[Service]
Type=simple
User=root
WorkingDirectory={APP_DIR}

Environment="PYTHONUNBUFFERED=1"
EnvironmentFile={APP_DIR}/.env

ExecStart={APP_DIR}/venv/bin/gunicorn --worker-class gevent --workers 2 --bind 0.0.0.0:5000 --timeout 120 --access-logfile {APP_DIR}/logs/access.log --error-logfile {APP_DIR}/logs/error.log wsgi:app

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
"""
    try:
        os.makedirs(os.path.join(APP_DIR, 'logs'), exist_ok=True)
        with open('/etc/systemd/system/samba-web.service', 'w',
                  encoding='utf-8') as f:
            f.write(service_content)
        subprocess.run(['systemctl', 'daemon-reload'],
                       check=False, capture_output=True)
        subprocess.run(['systemctl', 'enable', 'samba-web'],
                       check=False, capture_output=True)
        subprocess.run(['systemctl', 'restart', 'samba-web'],
                       check=False, capture_output=True)
        return True, 'Сервис создан и запущен'
    except Exception as e:
        return False, str(e)


# ============================================================
# ВЕБ-ИНТЕРФЕЙС
# ============================================================

_system_check_cache = {'data': None, 'ts': 0}
_SYSTEM_CHECK_TTL = 30


@app.route('/')
def index():
    """Отдаём HTML как статику — без Jinja2 (чтобы не ломать CSS/JS)."""
    return send_from_directory(
        os.path.join(TEMPLATES_DIR, 'installer'),
        'index.html',
        mimetype='text/html',
    )


@app.route('/favicon.ico')
def favicon():
    return '', 204


@app.route('/api/system-check')
def api_system_check():
    now = time.time()
    if (_system_check_cache['data'] is None
            or now - _system_check_cache['ts'] > _SYSTEM_CHECK_TTL):
        _system_check_cache['data'] = get_system_info()
        _system_check_cache['ts'] = now
    return jsonify(_system_check_cache['data'])


@app.route('/api/installed')
def api_installed():
    """Что уже установлено в системе (для UI)."""
    p = check_packages()
    return jsonify({
        'samba': {
            'installed': p['samba']['installed'],
            'version': p['samba']['version'],
            'service_active': p['smbd_active']['installed'],
        },
        'python': {
            'installed': p['python3']['installed'],
            'version': p['python3']['version'],
            'pip': p['python3-pip']['installed'],
            'venv': p['python3-venv']['installed'],
        },
        'web': {
            'app_installed': p['app_installed']['installed'],
            'venv_installed': p['venv_installed']['installed'],
            'env_installed': p['env_installed']['installed'],
            'service_active': p['app_service']['installed'],
        },
        'disks': {
            'installed': p['acl']['installed'],
            'version': p['acl']['version'],
        },
        'rsync': {
            'installed': p['rsync']['installed'],
        },
    })


@app.route('/api/install', methods=['POST'])
def api_install():
    """Установка компонентов с пропуском уже установленных."""
    data = request.get_json(silent=True) or {}
    components = data.get('components', [])
    admin_username = (data.get('admin_username') or 'admin').strip()
    admin_password = data.get('admin_password', '')
    force_reinstall = bool(data.get('force_reinstall', False))

    # Если force_reinstall и пусто — ставим всё
    if force_reinstall and not components:
        components = ['samba', 'python', 'web']

    if not components:
        return jsonify({'error': 'Не выбраны компоненты'}), 400

    if not admin_password or len(admin_password) < 6:
        return jsonify({'error': 'Пароль минимум 6 символов'}), 400

    if len(admin_username) < 3:
        return jsonify({'error': 'Логин минимум 3 символа'}), 400

    installed = check_packages()
    results = {}
    skipped = []

    # ---------- Samba ----------
    if 'samba' in components:
        if installed['samba']['installed'] and not force_reinstall:
            skipped.append({
                'component': 'samba',
                'message': (
                    f"Samba {installed['samba']['version']} "
                    f"уже установлена — пропускаю"
                ),
            })
        else:
            for pkg in ('samba', 'smbclient', 'cifs-utils'):
                ok, out = install_package(pkg)
                results[pkg] = {'success': ok, 'output': out}

    # ---------- Python ----------
    if 'python' in components or 'web' in components:
        for pkg in ('python3', 'python3-pip', 'python3-venv'):
            if installed[pkg]['installed'] and not force_reinstall:
                skipped.append({
                    'component': pkg,
                    'message': f'{pkg} уже установлен — пропускаю',
                })
            else:
                ok, out = install_package(pkg)
                results[pkg] = {'success': ok, 'output': out}

    # ---------- Диски (acl) ----------
    if 'disks' in components:
        if installed['acl']['installed'] and not force_reinstall:
            skipped.append({
                'component': 'acl',
                'message': 'acl уже установлен — пропускаю',
            })
        else:
            ok, out = install_package('acl')
            results['acl'] = {'success': ok, 'output': out}

    # ---------- Настройка Samba ----------
    if 'samba' in components:
        smb_conf = '/etc/samba/smb.conf'
        if not os.path.exists(smb_conf) or os.path.getsize(smb_conf) == 0:
            os.makedirs('/etc/samba', exist_ok=True)
            with open(smb_conf, 'w', encoding='utf-8') as f:
                f.write("""[global]
   workgroup = WORKGROUP
   server string = Samba Web Manager
   netbios name = SAMBA
   security = user
   map to guest = Bad User
   guest account = nobody
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes
""")
            results['smb_conf'] = {
                'success': True, 'output': 'smb.conf создан',
            }
        else:
            skipped.append({
                'component': 'smb_conf',
                'message': 'smb.conf уже существует — пропускаю',
            })

        os.makedirs('/srv/samba/public', exist_ok=True)
        os.chmod('/srv/samba/public', 0o777)

        with open(smb_conf, 'r', encoding='utf-8') as f:
            content = f.read()
        if '[public]' not in content:
            setup_samba_share('public', '/srv/samba/public',
                              read_only=False, guest_ok=True)
            results['samba_public_share'] = {
                'success': True, 'output': 'Шара [public] добавлена',
            }
        else:
            skipped.append({
                'component': 'samba_public_share',
                'message': 'Шара [public] уже существует — пропускаю',
            })

        restart_samba()

        if _samba_user_exists(admin_username) and not force_reinstall:
            skipped.append({
                'component': 'admin_user',
                'message': (
                    f"Samba-пользователь {admin_username} "
                    f"уже существует — пропускаю"
                ),
            })
        else:
            ok = create_samba_user(admin_username, admin_password)
            results['admin_user'] = {
                'success': ok,
                'output': f'Пользователь {admin_username}',
            }

    # ---------- .env ----------
    if 'web' in components:
        env_path = os.path.join(APP_DIR, '.env')
        if os.path.exists(env_path) and not force_reinstall:
            skipped.append({
                'component': 'env_file',
                'message': '.env уже существует — пропускаю',
            })
        else:
            try:
                create_env_file(admin_username, admin_password)
                results['env_file'] = {
                    'success': True, 'output': env_path,
                }
            except Exception as e:
                results['env_file'] = {
                    'success': False, 'output': str(e),
                }

    # ---------- Копирование файлов ----------
    if 'web' in components:
        if (installed['app_installed']['installed']
                and not force_reinstall):
            skipped.append({
                'component': 'copy_files',
                'message': (
                    f'{APP_DIR} уже существует — пропускаю '
                    f'(включите "Переустановить" для обновления)'
                ),
            })
        else:
            ok, msg = install_app_files()
            results['copy_files'] = {'success': ok, 'output': msg}
            if not ok:
                return jsonify({
                    'error': msg,
                    'results': results,
                    'skipped': skipped,
                }), 500

    # ---------- venv ----------
    if 'web' in components:
        if (installed['venv_installed']['installed']
                and not force_reinstall):
            skipped.append({
                'component': 'venv',
                'message': 'venv уже создан — пропускаю',
            })
        else:
            ok, msg = create_venv_and_install()
            results['venv'] = {'success': ok, 'output': msg}
            if not ok:
                return jsonify({
                    'error': msg,
                    'results': results,
                    'skipped': skipped,
                }), 500

    # ---------- systemd ----------
    if 'web' in components:
        if (installed['app_service']['installed']
                and not force_reinstall):
            subprocess.run(
                ['systemctl', 'restart', 'samba-web'],
                check=False, capture_output=True,
            )
            skipped.append({
                'component': 'systemd',
                'message': 'Сервис уже активен — перезапустил',
            })
        else:
            ok, msg = create_systemd_service()
            results['systemd'] = {'success': ok, 'output': msg}

    return jsonify({
        'success': True,
        'results': results,
        'skipped': skipped,
        'message': 'Установка завершена',
    })


@app.route('/api/install-app', methods=['POST'])
def api_install_app():
    """Копирование + venv + systemd (с пропуском)."""
    try:
        data = request.get_json(silent=True) or {}
        force_reinstall = bool(data.get('force_reinstall', False))

        installed = check_packages()
        skipped = []

        if (installed['app_installed']['installed']
                and not force_reinstall):
            skipped.append({
                'component': 'copy_files',
                'message': 'Файлы уже установлены — пропускаю',
            })
        else:
            ok, msg = install_app_files()
            if not ok:
                return jsonify({'error': msg}), 500

        if (installed['venv_installed']['installed']
                and not force_reinstall):
            skipped.append({
                'component': 'venv',
                'message': 'venv уже создан — пропускаю',
            })
        else:
            ok, msg = create_venv_and_install()
            if not ok:
                return jsonify({'error': msg}), 500

        ok, msg = create_systemd_service()
        if not ok:
            return jsonify({'error': msg}), 500

        return jsonify({
            'success': True,
            'message': msg,
            'skipped': skipped,
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ============================================================
# ЗАПУСК
# ============================================================

if __name__ == '__main__':
    if os.geteuid() != 0:
        print("⚠️  Для установки требуются права root!")
        print("   Запустите: sudo python3 installer_app.py")
        sys.exit(1)

    index_tpl = os.path.join(TEMPLATES_DIR, 'installer', 'index.html')
    if not os.path.exists(index_tpl):
        print(f"⚠️  Не найден шаблон: {index_tpl}")
        print("   Убедитесь, что templates/installer/index.html рядом.")
        sys.exit(1)

    if not find_app_source():
        print("⚠️  Не найдена папка samba-web-manager/ рядом с установщиком.")
        print("   Установка веб-интерфейса не сможет скопировать файлы.")

    print("🚀 Samba Web Manager - Веб-установщик")
    print("🌐 Откройте в браузере: http://<IP-сервера>:5001")
    print("   Локально:            http://localhost:5001")
    print()

    app.run(host='0.0.0.0', port=5001, debug=False)
