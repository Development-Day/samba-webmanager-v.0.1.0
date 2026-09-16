.PHONY: help install dev prod backup restore test clean

help:
	@echo "Доступные команды:"
	@echo "  make install   - Установка приложения"
	@echo "  make dev       - Запуск в режиме разработки"
	@echo "  make prod      - Запуск в production режиме"
	@echo "  make backup    - Создать бэкап конфига"
	@echo "  make restore   - Восстановить из бэкапа"
	@echo "  make test      - Запуск тестов"
	@echo "  make clean     - Очистка временных файлов"

install:
	@echo "Установка..."
	pip install -r requirements.txt
	@echo "Создание .env файла..."
	test -f .env || cp .env.example .env

dev:
	export FLASK_ENV=development && python app.py

prod:
	gunicorn --worker-class gevent --workers 4 --bind 0.0.0.0:5000 wsgi:app

backup:
	python -c "from samba_manager.backup import create_backup; print(create_backup())"

restore:
	python -c "from samba_manager.backup import restore_backup; restore_backup('$(FILE)')"

test:
	pytest tests/ -v --cov=samba_manager

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	rm -rf .pytest_cache .coverage htmlcov

docker-build:
	docker-compose -f deploy/docker-compose.prod.yml build

docker-up:
	docker-compose -f deploy/docker-compose.prod.yml up -d

docker-down:
	docker-compose -f deploy/docker-compose.prod.yml down

docker-logs:
	docker-compose -f deploy/docker-compose.prod.yml logs -f