import os
from datetime import timedelta
from dotenv import load_dotenv

# Загружаем .env из корня проекта
BASE_DIR = os.path.abspath(os.path.dirname(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))


def _str2bool(value: str) -> bool:
    return str(value).strip().lower() in ('1', 'true', 'yes', 'on')


def _parse_hosts(value: str):
    value = (value or '*').strip()
    if value == '*':
        return '*'
    return [h.strip() for h in value.split(',') if h.strip()]


class Config:
    """Базовые настройки"""
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev-secret-key-change-in-production'
    PERMANENT_SESSION_LIFETIME = timedelta(hours=8)

    SESSION_COOKIE_SECURE = _str2bool(os.environ.get('SESSION_COOKIE_SECURE', 'False'))
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = 'Lax'

    SAMBA_CONFIG = os.environ.get('SAMBA_CONFIG', '/etc/samba/smb.conf')
    SAMBA_PASSWD = os.environ.get('SAMBA_PASSWD', '/etc/samba/smbpasswd')

    APP_NAME = 'Samba Web Manager'
    APP_VERSION = '1.0.0'

    LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')
    LOG_FILE = os.path.join(BASE_DIR, 'logs', 'app.log')
    LOG_MAX_BYTES = 10 * 1024 * 1024
    LOG_BACKUP_COUNT = 10

    BACKUP_DIR = os.path.join(BASE_DIR, 'backups')
    BACKUP_MAX_COUNT = 10

    ADMIN_USERNAME = os.environ.get('ADMIN_USERNAME', 'admin')
    ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', 'admin123')
    ADMIN_PASSWORD_HASH = os.environ.get('ADMIN_PASSWORD_HASH')

    ALLOWED_HOSTS = _parse_hosts(os.environ.get('ALLOWED_HOSTS', '*'))


class DevelopmentConfig(Config):
    DEBUG = True
    TESTING = False
    SESSION_COOKIE_SECURE = False
    LOG_LEVEL = 'DEBUG'


class ProductionConfig(Config):
    DEBUG = False
    TESTING = False

    @classmethod
    def init_app(cls, app):
        import logging
        from logging.handlers import RotatingFileHandler

        # КРИТИЧНО: проверяем SECRET_KEY
        if not cls.SECRET_KEY or cls.SECRET_KEY == 'dev-secret-key-change-in-production':
            raise RuntimeError(
                "SECRET_KEY не задан или используется значение по умолчанию!\n"
                "Сгенерируйте и добавьте в .env:\n"
                "  python3 -c \"import secrets; print(secrets.token_hex(32))\""
            )

        log_dir = os.path.dirname(cls.LOG_FILE)
        os.makedirs(log_dir, exist_ok=True)
        os.makedirs(cls.BACKUP_DIR, exist_ok=True)

        formatter = logging.Formatter(
            '%(asctime)s %(levelname)s: %(message)s [in %(pathname)s:%(lineno)d]'
        )

        file_handler = RotatingFileHandler(
            cls.LOG_FILE,
            maxBytes=cls.LOG_MAX_BYTES,
            backupCount=cls.LOG_BACKUP_COUNT,
        )
        file_handler.setFormatter(formatter)
        file_handler.setLevel(getattr(logging, cls.LOG_LEVEL))

        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)
        console_handler.setLevel(logging.INFO)

        app.logger.addHandler(file_handler)
        app.logger.addHandler(console_handler)
        app.logger.setLevel(getattr(logging, cls.LOG_LEVEL))

        app.logger.info(f'{cls.APP_NAME} v{cls.APP_VERSION} запущен')


class TestingConfig(Config):
    TESTING = True
    DEBUG = True
    SAMBA_CONFIG = 'tests/test_smb.conf'
    LOG_LEVEL = 'ERROR'


config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'testing': TestingConfig,
    'default': DevelopmentConfig,
}