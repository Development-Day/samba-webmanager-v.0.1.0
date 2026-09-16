# 1. Клонирование/создание структуры

mkdir samba-web-manager \&\& cd samba-web-manager



# 2. Создать все файлы согласно структуре выше



# 3. Установка зависимостей

pip install -r requirements.txt



# 4. Настройка .env

cp .env.example .env

nano .env  # отредактируйте пароли



# 5. Запуск (режим разработки)

make dev



# 6. Production запуск

make prod



# 7. Docker-запуск

make docker-build

make docker-up

