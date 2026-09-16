#!/usr/bin/env python3
"""
WSGI-точка входа для gunicorn.

Запуск в продакшене:
    gunicorn --worker-class gevent --workers 2 --bind 0.0.0.0:5000 wsgi:app

Запуск для отладки:
    python wsgi.py
"""
import os
import sys

from app import create_app

# Определяем окружение: APP_ENV (новое) или FLASK_ENV (для совместимости)
config_name = (
    os.environ.get('APP_ENV')
    or os.environ.get('FLASK_ENV')
    or 'production'
)

try:
    app = create_app(config_name)
except Exception as exc:
    print(f"❌ Ошибка инициализации приложения: {exc}", file=sys.stderr, flush=True)
    raise

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    debug = config_name == 'development'
    app.run(host='0.0.0.0', port=port, debug=debug)