import pytest
import json
from app import create_app

@pytest.fixture
def client():
    """Создание тестового клиента"""
    app = create_app('testing')
    app.testing = True
    with app.test_client() as client:
        # Авторизация для тестов
        client.post('/login', data={
            'username': 'admin',
            'password': 'admin123'
        })
        yield client

def test_login(client):
    """Тест входа"""
    response = client.get('/')
    assert response.status_code == 200

def test_get_shares(client):
    """Тест получения шар"""
    response = client.get('/api/shares')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert isinstance(data, list)

def test_get_users(client):
    """Тест получения пользователей"""
    response = client.get('/api/users')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert isinstance(data, list)

def test_get_status(client):
    """Тест получения статуса"""
    response = client.get('/api/status')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert 'active' in data

def test_get_system_info(client):
    """Тест получения системной информации"""
    response = client.get('/api/system/info')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert 'hostname' in data
    assert 'cpu' in data
    assert 'memory' in data