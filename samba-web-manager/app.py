#!/usr/bin/env python3
"""
Samba Web Manager - Главное приложение

Веб-интерфейс для управления Samba-сервером.
Только для Linux (Debian 11+, Ubuntu 20.04+).
"""

import os
import re
import subprocess
from datetime import datetime
from functools import wraps

import bcrypt
from flask import (
    Flask, render_template, request, jsonify,
    session, redirect, url_for, flash,
)

from config import config
from samba_manager import config_parser, users, service, validator, backup, monitoring
from samba_manager.disks import DiskAPI


# ============================================================
# ФАБРИКА ПРИЛОЖЕНИЙ
# ============================================================

def create_app(config_name='default'):
    """Создание и настройка Flask-приложения"""
    app = Flask(__name__)
    app.config.from_object(config[config_name])
    app.config['config_name'] = config_name

    # Инициализация DiskAPI
    disk_api = DiskAPI()

    # Инициализация логов для production
    if config_name == 'production':
        from config import ProductionConfig
        ProductionConfig.init_app(app)

    # ========================================================
    # КОНТЕКСТНЫЕ ПРОЦЕССОРЫ
    # ========================================================

    @app.context_processor
    def inject_globals():
        return {
            'app_name': app.config.get('APP_NAME', 'Samba Web Manager'),
            'app_version': app.config.get('APP_VERSION', '1.0.0'),
            'year': datetime.now().year,
        }

    @app.template_filter('datetime')
    def format_datetime(value):
        if isinstance(value, str):
            try:
                value = datetime.fromisoformat(value)
            except (ValueError, TypeError):
                return value
        return value.strftime('%Y-%m-%d %H:%M:%S')

    @app.template_filter('filesize')
    def format_filesize(size):
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size < 1024.0:
                return f"{size:.1f} {unit}"
            size /= 1024.0
        return f"{size:.1f} PB"

    # ========================================================
    # ДЕКОРАТОРЫ
    # ========================================================

    def login_required(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not session.get('logged_in'):
                if request.path.startswith('/api/'):
                    return jsonify({'error': 'Не авторизован'}), 401
                return redirect(url_for('login'))
            return f(*args, **kwargs)
        return decorated_function

    def admin_required(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not session.get('is_admin'):
                flash('Доступ запрещен', 'danger')
                return redirect(url_for('index'))
            return f(*args, **kwargs)
        return decorated_function

    def log_action(action):
        def decorator(f):
            @wraps(f)
            def decorated_function(*args, **kwargs):
                username = session.get('username', 'anonymous')
                ip = request.remote_addr
                app.logger.info(f'[{ip}] {username} - {action}')
                return f(*args, **kwargs)
            return decorated_function
        return decorator

    # ========================================================
    # ОБРАБОТЧИКИ ОШИБОК
    # ========================================================

    @app.errorhandler(404)
    def not_found(e):
        if request.path.startswith('/api/'):
            return jsonify({'error': 'Ресурс не найден'}), 404
        return render_template('errors/404.html'), 404

    @app.errorhandler(500)
    def internal_error(e):
        app.logger.error(f'Внутренняя ошибка: {e}')
        if request.path.startswith('/api/'):
            return jsonify({'error': 'Внутренняя ошибка сервера'}), 500
        return render_template('errors/500.html'), 500

    @app.errorhandler(403)
    def forbidden(e):
        if request.path.startswith('/api/'):
            return jsonify({'error': 'Доступ запрещен'}), 403
        return render_template('errors/403.html'), 403

    # ========================================================
    # HEALTHCHECK + FAVICON (без авторизации)
    # ========================================================

    @app.route('/health', methods=['GET'])
    def health():
        """Проверка живости сервиса. Используется install.sh и мониторингом."""
        return jsonify({
            'status': 'ok',
            'name': app.config.get('APP_NAME', 'Samba Web Manager'),
            'version': app.config.get('APP_VERSION', '1.0.0'),
        }), 200

    @app.route('/favicon.ico')
    def favicon():
        """Заглушка для favicon — убирает 404 из логов."""
        return '', 204

    # ========================================================
    # АУТЕНТИФИКАЦИЯ
    # ========================================================

    @app.route('/login', methods=['GET', 'POST'])
    def login():
        if session.get('logged_in'):
            return redirect(url_for('index'))

        if request.method == 'POST':
            username = request.form.get('username', '').strip()
            password = request.form.get('password', '')

            # 1. Проверка имени
            if username != app.config.get('ADMIN_USERNAME', 'admin'):
                flash('Неверное имя пользователя или пароль', 'danger')
                app.logger.warning(
                    f'Неудачная попытка входа: {username!r} с {request.remote_addr}'
                )
                return render_template('login.html')

            # 2. Проверка пароля: bcrypt-хеш имеет приоритет, иначе — plaintext
            password_hash = app.config.get('ADMIN_PASSWORD_HASH')
            if password_hash:
                try:
                    ok = bcrypt.checkpw(
                        password.encode('utf-8'),
                        password_hash.encode('utf-8'),
                    )
                except (ValueError, TypeError) as exc:
                    app.logger.error(f'Некорректный ADMIN_PASSWORD_HASH: {exc}')
                    ok = False
            else:
                expected = app.config.get('ADMIN_PASSWORD', '')
                ok = bool(expected) and (password == expected)

            # 3. Успех / неудача
            if ok:
                session['logged_in'] = True
                session['username'] = username
                session['is_admin'] = True
                session.permanent = True
                app.logger.info(
                    f'Пользователь {username} вошёл с {request.remote_addr}'
                )
                return redirect(url_for('index'))

            flash('Неверное имя пользователя или пароль', 'danger')
            app.logger.warning(
                f'Неудачная попытка входа: {username!r} с {request.remote_addr}'
            )

        return render_template('login.html')

    @app.route('/logout')
    def logout():
        username = session.get('username', 'unknown')
        app.logger.info(f'Пользователь {username} вышел из системы')
        session.clear()
        response = redirect(url_for('login'))
        response.set_cookie(
            'session', '', expires=0,
            httponly=True, samesite='Lax', path='/',
        )
        response.delete_cookie('session', path='/')
        return response

    # ========================================================
    # СТРАНИЦЫ
    # ========================================================

    @app.route('/')
    @login_required
    def index():
        samba_status = service.get_status()
        samba_config = config_parser.SambaConfig()
        shares = samba_config.get_shares()
        users_list = users.get_samba_users()

        import psutil
        disk = psutil.disk_usage('/')

        # ---- Список всех дисков (для Jinja2-контекста и JS) ----
        disks = []
        mounted_disks = []
        try:
            status_data = disk_api.get_disk_status()
            disks = status_data.get('disks', [])
            mounted_disks = [
                d for d in disks
                if d.get('is_mounted')
                and d.get('mount_point')
                and d.get('filesystem') != 'swap'
                and d.get('mount_point') != '[SWAP]'
            ]
        except Exception as e:
            app.logger.warning(f'Не удалось получить список дисков: {e}')

        stats = {
            'shares': len(shares),
            'users': len(users_list),
            'connections': monitoring.get_active_connections(),
            'uptime': service.get_uptime(),
            'disks': len(mounted_disks),
            'disks_total': len(disks),
            'disks_mounted': len(mounted_disks),
        }

        return render_template(
            'index.html',
            status=samba_status,
            stats=stats,
            disk=disk,
            shares=shares[:5],
            disks=mounted_disks,
            total_disks=len(disks),
            mounted_count=len(mounted_disks),
        )

    @app.route('/shares')
    @login_required
    def shares_page():
        return render_template('shares.html')

    @app.route('/users')
    @login_required
    def users_page():
        return render_template('users.html')

    @app.route('/disks')
    @login_required
    def disks_page():
        return render_template('disks.html')

    @app.route('/logs')
    @login_required
    def logs_page():
        log_file = app.config.get('LOG_FILE', 'logs/app.log')
        logs = []
        if os.path.exists(log_file):
            with open(log_file, 'r', encoding='utf-8', errors='replace') as f:
                logs = f.readlines()[-200:]
        return render_template('logs.html', logs=logs)

    @app.route('/backups')
    @login_required
    def backups_page():
        backup_files = backup.list_backups()
        return render_template('backups.html', backups=backup_files)

    @app.route('/monitoring')
    @login_required
    def monitoring_page():
        return render_template('monitoring.html')

    # ========================================================
    # API: ШАРЫ
    # ========================================================

    @app.route('/api/shares', methods=['GET'])
    @login_required
    @log_action('Просмотр списка шар')
    def api_get_shares():
        samba_config = config_parser.SambaConfig()
        return jsonify(samba_config.get_shares())

    @app.route('/api/shares', methods=['POST'])
    @login_required
    @log_action('Создание шары')
    def api_add_share():
        data = request.json or {}
        name = (data.get('name') or '').strip()
        path = (data.get('path') or '').strip()

        if not name or not path:
            return jsonify({'error': 'Имя и путь обязательны'}), 400

        if not os.path.exists(path):
            return jsonify({'error': f'Папка {path} не существует'}), 400

        if not re.match(r'^[a-zA-Z0-9_\-.]+$', name):
            return jsonify({'error': 'Имя содержит недопустимые символы'}), 400

        try:
            samba_config = config_parser.SambaConfig()
            samba_config.add_share(
                name=name,
                path=path,
                read_only=data.get('read_only', True),
                guest_ok=data.get('guest_ok', False),
                valid_users=data.get('valid_users', ''),
                comment=data.get('comment', ''),
            )
            service.restart()
            app.logger.info(f'Создана шара: {name} -> {path}')
            return jsonify({'message': f'Шара {name} создана', 'name': name}), 201
        except Exception as e:
            app.logger.error(f'Ошибка создания шары {name}: {e}')
            return jsonify({'error': str(e)}), 500

    @app.route('/api/shares/<name>', methods=['PUT'])
    @login_required
    @log_action('Обновление шары')
    def api_update_share(name):
        data = request.json or {}
        try:
            samba_config = config_parser.SambaConfig()
            samba_config.update_share(name, data)
            service.restart()
            app.logger.info(f'Обновлена шара: {name}')
            return jsonify({'message': f'Шара {name} обновлена'})
        except Exception as e:
            app.logger.error(f'Ошибка обновления шары {name}: {e}')
            return jsonify({'error': str(e)}), 500

    @app.route('/api/shares/<name>', methods=['DELETE'])
    @login_required
    @log_action('Удаление шары')
    def api_delete_share(name):
        try:
            samba_config = config_parser.SambaConfig()
            backup.create_backup()
            samba_config.delete_share(name)
            service.restart()
            app.logger.info(f'Удалена шара: {name}')
            return jsonify({'message': f'Шара {name} удалена'})
        except Exception as e:
            app.logger.error(f'Ошибка удаления шары {name}: {e}')
            return jsonify({'error': str(e)}), 500

    # ========================================================
    # API: ПОЛЬЗОВАТЕЛИ
    # ========================================================

    @app.route('/api/users', methods=['GET'])
    @login_required
    @log_action('Просмотр пользователей')
    def api_get_users():
        return jsonify(users.get_samba_users())

    @app.route('/api/users', methods=['POST'])
    @login_required
    @log_action('Создание пользователя')
    def api_add_user():
        data = request.json or {}
        username = (data.get('username') or '').strip()
        password = data.get('password', '')

        if not username or not password:
            return jsonify({'error': 'Имя и пароль обязательны'}), 400

        if len(username) < 3:
            return jsonify({'error': 'Имя должно быть не менее 3 символов'}), 400

        if len(password) < 8:
            return jsonify({'error': 'Пароль должен быть не менее 8 символов'}), 400

        if users.system_user_exists(username):
            return jsonify({'error': 'Пользователь уже существует в системе'}), 400

        try:
            users.add_user(username, password)
            app.logger.info(f'Создан пользователь: {username}')
            return jsonify({'message': f'Пользователь {username} добавлен'}), 201
        except Exception as e:
            app.logger.error(f'Ошибка создания пользователя {username}: {e}')
            return jsonify({'error': str(e)}), 500

    @app.route('/api/users/<username>', methods=['DELETE'])
    @login_required
    @log_action('Удаление пользователя')
    def api_delete_user(username):
        try:
            users.delete_user(username)
            app.logger.info(f'Удален пользователь: {username}')
            return jsonify({'message': f'Пользователь {username} удален'})
        except Exception as e:
            return jsonify({'error': str(e)}), 500

    @app.route('/api/users/<username>/password', methods=['POST'])
    @login_required
    @log_action('Смена пароля пользователя')
    def api_change_password(username):
        data = request.json or {}
        password = data.get('password', '')

        if not password or len(password) < 8:
            return jsonify({'error': 'Пароль должен быть не менее 8 символов'}), 400

        try:
            users.set_password(username, password)
            app.logger.info(f'Сменен пароль для пользователя: {username}')
            return jsonify({'message': f'Пароль для {username} изменен'})
        except Exception as e:
            return jsonify({'error': str(e)}), 500

    @app.route('/api/users/<username>/enable', methods=['POST'])
    @login_required
    @log_action('Включение пользователя')
    def api_enable_user(username):
        try:
            users.enable_user(username)
            return jsonify({'message': f'Пользователь {username} включен'})
        except Exception as e:
            return jsonify({'error': str(e)}), 500

    @app.route('/api/users/<username>/disable', methods=['POST'])
    @login_required
    @log_action('Отключение пользователя')
    def api_disable_user(username):
        try:
            users.disable_user(username)
            return jsonify({'message': f'Пользователь {username} отключен'})
        except Exception as e:
            return jsonify({'error': str(e)}), 500

    # ========================================================
    # API: ДИСКИ
    # ========================================================

    @app.route('/api/disks', methods=['GET'])
    @login_required
    @log_action('Просмотр дисков')
    def api_get_disks():
        try:
            return jsonify(disk_api.get_disk_status())
        except Exception as e:
            app.logger.error(f'Ошибка получения информации о дисках: {e}')
            return jsonify({'error': str(e)}), 500

    @app.route('/api/disks/mount', methods=['POST'])
    @login_required
    @log_action('Монтирование диска')
    def api_mount_disk():
        data = request.json or {}
        device = data.get('device')
        mount_point = data.get('mount_point')
        options = data.get('options', {})

        if not device or not mount_point:
            return jsonify({'error': 'Device и mount_point обязательны'}), 400

        result = disk_api.mount_disk_api(device, mount_point, options)

        if result.get('success'):
            if data.get('create_share', True):
                share_name = os.path.basename(mount_point)
                samba_config = config_parser.SambaConfig()
                try:
                    samba_config.add_share(
                        name=share_name,
                        path=mount_point,
                        read_only=False,
                        guest_ok=True,
                        comment=f'Диск {device}',
                    )
                    service.restart()
                except Exception as e:
                    app.logger.warning(f'Не удалось создать шару: {e}')
            return jsonify(result)
        return jsonify(result), 500

    @app.route('/api/disks/unmount', methods=['POST'])
    @login_required
    @log_action('Отмонтирование диска')
    def api_unmount_disk():
        data = request.json or {}
        mount_point = data.get('mount_point')
        remove_fstab = data.get('remove_fstab', False)
        remove_share = data.get('remove_share', False)

        if not mount_point:
            return jsonify({'error': 'mount_point обязателен'}), 400

        if remove_share:
            share_name = os.path.basename(mount_point)
            try:
                samba_config = config_parser.SambaConfig()
                samba_config.delete_share(share_name)
                service.restart()
            except Exception as e:
                app.logger.warning(f'Не удалось удалить шару: {e}')

        result = disk_api.unmount_disk_api(mount_point, remove_fstab)

        if result.get('success'):
            return jsonify(result)
        return jsonify(result), 500

    @app.route('/api/disks/mount-points', methods=['GET'])
    @login_required
    def api_get_mount_points():
        try:
            points = disk_api.manager.get_available_mount_points()
            return jsonify({'mount_points': points})
        except Exception as e:
            return jsonify({'error': str(e)}), 500

    @app.route('/api/disks/mount-points', methods=['POST'])
    @login_required
    @log_action('Создание точки монтирования')
    def api_create_mount_point():
        data = request.json or {}
        name = (data.get('name') or '').strip()

        if not name:
            return jsonify({'error': 'Имя обязательно'}), 400

        name = re.sub(r'[^a-zA-Z0-9_-]', '_', name)

        try:
            mount_point = disk_api.manager.create_mount_point(name)
            return jsonify({
                'success': True,
                'mount_point': mount_point,
                'message': f'Точка монтирования {mount_point} создана',
            })
        except Exception as e:
            return jsonify({'error': str(e)}), 500

    @app.route('/api/disks/auto-mount', methods=['POST'])
    @login_required
    @log_action('Автоматическое монтирование')
    def api_auto_mount():
        try:
            disk_api.manager.auto_mount_detected_disks()
            return jsonify({
                'success': True,
                'message': 'Автоматическое монтирование завершено',
            })
        except Exception as e:
            return jsonify({'error': str(e)}), 500

    # ========================================================
    # API: СИСТЕМА
    # ========================================================

    @app.route('/api/status', methods=['GET'])
    @login_required
    def api_get_status():
        return jsonify(service.get_status())

    @app.route('/api/restart', methods=['POST'])
    @login_required
    @log_action('Перезапуск Samba')
    def api_restart():
        try:
            backup.create_backup()
            service.restart()
            app.logger.info('Samba перезапущена')
            return jsonify({'message': 'Samba перезапущена успешно'})
        except Exception as e:
            app.logger.error(f'Ошибка перезапуска Samba: {e}')
            return jsonify({'error': str(e)}), 500

    @app.route('/api/system/info', methods=['GET'])
    @login_required
    def api_system_info():
        import psutil
        import platform

        # Полный список дисков через DiskAPI
        disks = []
        mounted_disks = []
        try:
            status = disk_api.get_disk_status()
            disks = status.get('disks', [])
            mounted_disks = [
                d for d in disks
                if d.get('is_mounted') and d.get('mount_point')
            ]
        except Exception as e:
            app.logger.warning(f'Не удалось получить список дисков: {e}')

        return jsonify({
            'hostname': platform.node(),
            'os': platform.platform(),
            'python': platform.python_version(),
            'cpu': {
                'cores': psutil.cpu_count(),
                'usage': psutil.cpu_percent(interval=1),
                'load_avg': os.getloadavg(),
            },
            'memory': {
                'total': psutil.virtual_memory().total,
                'available': psutil.virtual_memory().available,
                'used': psutil.virtual_memory().used,
                'percent': psutil.virtual_memory().percent,
            },
            # Старое поле — корень, для совместимости
            'disk': {
                'total': psutil.disk_usage('/').total,
                'used': psutil.disk_usage('/').used,
                'free': psutil.disk_usage('/').free,
                'percent': psutil.disk_usage('/').percent,
            },
            # НОВОЕ: список всех дисков
            'disks': disks,
            'mounted_disks': mounted_disks,
            'total_disks': len(disks),
            'uptime': service.get_uptime(),
        })

    @app.route('/api/monitoring/connections', methods=['GET'])
    @login_required
    def api_get_connections():
        return jsonify(monitoring.get_active_connections())

    @app.route('/api/backups', methods=['GET'])
    @login_required
    @log_action('Просмотр бэкапов')
    def api_get_backups():
        return jsonify(backup.list_backups())

    @app.route('/api/backups', methods=['POST'])
    @login_required
    @log_action('Создание бэкапа')
    def api_create_backup():
        try:
            backup_file = backup.create_backup()
            app.logger.info(f'Создан бэкап: {backup_file}')
            return jsonify({'message': 'Бэкап создан', 'file': backup_file})
        except Exception as e:
            app.logger.error(f'Ошибка создания бэкапа: {e}')
            return jsonify({'error': str(e)}), 500

    @app.route('/api/backups/<filename>', methods=['POST'])
    @login_required
    @log_action('Восстановление из бэкапа')
    def api_restore_backup(filename):
        try:
            backup.restore_backup(filename)
            service.restart()
            app.logger.info(f'Восстановлен бэкап: {filename}')
            return jsonify({'message': 'Бэкап восстановлен'})
        except Exception as e:
            app.logger.error(f'Ошибка восстановления бэкапа {filename}: {e}')
            return jsonify({'error': str(e)}), 500

    @app.route('/api/backups/<filename>', methods=['DELETE'])
    @login_required
    @log_action('Удаление бэкапа')
    def api_delete_backup(filename):
        try:
            backup.delete_backup(filename)
            app.logger.info(f'Удален бэкап: {filename}')
            return jsonify({'message': 'Бэкап удален'})
        except Exception as e:
            app.logger.error(f'Ошибка удаления бэкапа {filename}: {e}')
            return jsonify({'error': str(e)}), 500

    return app


# ============================================================
# ЗАПУСК (для отладки: python app.py)
# ============================================================

if __name__ == '__main__':
    os.makedirs('logs', exist_ok=True)

    config_name = (
        os.environ.get('APP_ENV')
        or os.environ.get('FLASK_ENV')
        or 'development'
    )
    app = create_app(config_name)

    port = int(os.environ.get('PORT', 5000))
    debug = (config_name == 'development')

    app.run(host='0.0.0.0', port=port, debug=debug)
