// ============================================================
// Samba Web Manager - Управление пользователями
// ============================================================

let usersCache = [];

// ============ ЗАГРУЗКА СПИСКА ============
function loadUsers() {
    fetch('/api/users')
        .then(r => r.json())
        .then(users => {
            usersCache = users;
            renderUsers(users);
        })
        .catch(err => {
            console.error('Ошибка загрузки пользователей:', err);
            showToast('Не удалось загрузить список пользователей', 'danger');
        });
}

function renderUsers(users) {
    const container = document.getElementById('users-list');
    if (!container) return;

    if (users.length === 0) {
        container.innerHTML = `
            <div class="text-center text-muted py-5">
                <i class="bi bi-people display-1"></i>
                <p>Нет пользователей Samba</p>
            </div>
        `;
        return;
    }

    let html = `
        <table>
            <thead>
                <tr>
                    <th>ИМЯ</th>
                    <th>UID</th>
                    <th>NT</th>
                    <th>ДЕЙСТВИЯ</th>
                </tr>
            </thead>
            <tbody>
    `;

    users.forEach(user => {
        html += `
            <tr>
                <td><i class="bi bi-person"></i> ${escapeHtml(user.username)}</td>
                <td>${escapeHtml(user.uid || '')}</td>
                <td>${escapeHtml(user.nt_username || '')}</td>
                <td>
                    <button onclick="changePassword('${escapeAttr(user.username)}')" class="btn btn-warning btn-sm">
                        <i class="bi bi-key"></i> ПАРОЛЬ
                    </button>
                    <button onclick="deleteUser('${escapeAttr(user.username)}')" class="btn btn-danger btn-sm">
                        <i class="bi bi-trash"></i>
                    </button>
                </td>
            </tr>
        `;
    });

    html += '</tbody></table>';
    container.innerHTML = html;
}

// ============ ДОБАВЛЕНИЕ ============
function showAddUser() {
    document.getElementById('userName').value = '';
    document.getElementById('userPassword').value = '';
    openModal('userModal');
}

// ============ СОХРАНЕНИЕ ============
function saveUser() {
    const username = document.getElementById('userName').value.trim();
    const password = document.getElementById('userPassword').value;

    if (!username || !password) {
        showToast('Заполните все поля', 'warning');
        return;
    }

    if (username.length < 3) {
        showToast('Имя должно быть не менее 3 символов', 'warning');
        return;
    }

    if (password.length < 8) {
        showToast('Пароль должен быть не менее 8 символов', 'warning');
        return;
    }

    fetch('/api/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password })
    })
    .then(r => r.json())
    .then(result => {
        if (result.error) {
            showToast('Ошибка: ' + result.error, 'danger');
        } else {
            showToast(result.message || 'Пользователь создан', 'success');
            closeModal('userModal');
            loadUsers();
        }
    })
    .catch(err => {
        showToast('Ошибка сети: ' + err.message, 'danger');
    });
}

// ============ УДАЛЕНИЕ ============
function deleteUser(username) {
    if (!confirm(`Удалить пользователя "${username}"?`)) return;

    fetch(`/api/users/${encodeURIComponent(username)}`, { method: 'DELETE' })
        .then(r => r.json())
        .then(result => {
            if (result.error) {
                showToast('Ошибка: ' + result.error, 'danger');
            } else {
                showToast(result.message || 'Пользователь удалён', 'success');
                loadUsers();
            }
        })
        .catch(err => {
            showToast('Ошибка сети: ' + err.message, 'danger');
        });
}

// ============ СМЕНА ПАРОЛЯ ============
function changePassword(username) {
    const password = prompt(`Введите новый пароль для ${username} (мин. 8 символов):`);
    if (!password) return;

    if (password.length < 8) {
        showToast('Пароль должен быть не менее 8 символов', 'warning');
        return;
    }

    fetch(`/api/users/${encodeURIComponent(username)}/password`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password })
    })
    .then(r => r.json())
    .then(result => {
        if (result.error) {
            showToast('Ошибка: ' + result.error, 'danger');
        } else {
            showToast(result.message || 'Пароль изменён', 'success');
        }
    })
    .catch(err => {
        showToast('Ошибка сети: ' + err.message, 'danger');
    });
}

// ============ УТИЛИТЫ ============
function escapeHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function escapeAttr(str) {
    if (!str) return '';
    return String(str)
        .replace(/\\/g, '\\\\')
        .replace(/'/g, "\\'")
        .replace(/"/g, '&quot;');
}

// ============ ИНИЦИАЛИЗАЦИЯ ============
document.addEventListener('DOMContentLoaded', loadUsers);

// Экспорт
window.loadUsers = loadUsers;
window.showAddUser = showAddUser;
window.saveUser = saveUser;
window.deleteUser = deleteUser;
window.changePassword = changePassword;
