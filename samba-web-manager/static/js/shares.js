// ============================================================
// Samba Web Manager - Управление шарами
// ============================================================

let sharesCache = [];

// ============ ЗАГРУЗКА СПИСКА ============
function loadShares() {
    fetch('/api/shares')
        .then(r => r.json())
        .then(shares => {
            sharesCache = shares;
            renderShares(shares);
        })
        .catch(err => {
            console.error('Ошибка загрузки шар:', err);
            showToast('Не удалось загрузить список шар', 'danger');
        });
}

function renderShares(shares) {
    const container = document.getElementById('shares-list');
    if (!container) return;

    if (shares.length === 0) {
        container.innerHTML = `
            <div class="text-center text-muted py-5">
                <i class="bi bi-folder display-1"></i>
                <p>Нет общих папок. Создайте первую!</p>
            </div>
        `;
        return;
    }

    let html = '<div class="row">';
    shares.forEach(share => {
        html += `
            <div class="col-md-6">
                <div class="card">
                    <h3><i class="bi bi-folder"></i> ${escapeHtml(share.name)}</h3>
                    <p class="text-muted mb-2">${escapeHtml(share.path)}</p>
                    <div class="mb-3">
                        ${share.read_only
                            ? '<span class="badge badge-warning">ТОЛЬКО ЧТЕНИЕ</span>'
                            : '<span class="badge badge-success">ЧТЕНИЕ/ЗАПИСЬ</span>'}
                        ${share.guest_ok ? '<span class="badge badge-info">ГОСТИ</span>' : ''}
                        ${share.valid_users
                            ? '<span class="badge badge-secondary">' + escapeHtml(share.valid_users) + '</span>'
                            : ''}
                    </div>
                    ${share.comment
                        ? '<p class="text-muted mb-3"><i class="bi bi-chat"></i> ' + escapeHtml(share.comment) + '</p>'
                        : ''}
                    <div class="d-flex gap-2">
                        <button onclick="editShare('${escapeAttr(share.name)}')" class="btn btn-warning btn-sm">
                            <i class="bi bi-pencil"></i> ИЗМЕНИТЬ
                        </button>
                        <button onclick="deleteShare('${escapeAttr(share.name)}')" class="btn btn-danger btn-sm">
                            <i class="bi bi-trash"></i> УДАЛИТЬ
                        </button>
                    </div>
                </div>
            </div>
        `;
    });
    html += '</div>';
    container.innerHTML = html;
}

// ============ ДОБАВЛЕНИЕ ============
function showAddShare() {
    document.getElementById('shareModalTitle').textContent = 'ДОБАВИТЬ ШАРУ';
    document.getElementById('shareNameEdit').value = '';
    document.getElementById('shareName').value = '';
    document.getElementById('shareName').disabled = false;
    document.getElementById('sharePath').value = '';
    document.getElementById('shareReadOnly').checked = true;
    document.getElementById('shareGuestOk').checked = false;
    document.getElementById('shareValidUsers').value = '';
    document.getElementById('shareComment').value = '';
    openModal('shareModal');
}

// ============ РЕДАКТИРОВАНИЕ ============
function editShare(name) {
    const share = sharesCache.find(s => s.name === name);
    if (!share) {
        showToast('Шара не найдена', 'danger');
        return;
    }

    document.getElementById('shareModalTitle').textContent = 'РЕДАКТИРОВАТЬ ШАРУ';
    document.getElementById('shareNameEdit').value = name;
    document.getElementById('shareName').value = share.name;
    document.getElementById('shareName').disabled = true;
    document.getElementById('sharePath').value = share.path;
    document.getElementById('shareReadOnly').checked = share.read_only;
    document.getElementById('shareGuestOk').checked = share.guest_ok;
    document.getElementById('shareValidUsers').value = share.valid_users || '';
    document.getElementById('shareComment').value = share.comment || '';
    openModal('shareModal');
}

// ============ СОХРАНЕНИЕ ============
function saveShare() {
    const name = document.getElementById('shareName').value.trim();
    const path = document.getElementById('sharePath').value.trim();
    const read_only = document.getElementById('shareReadOnly').checked;
    const guest_ok = document.getElementById('shareGuestOk').checked;
    const valid_users = document.getElementById('shareValidUsers').value.trim();
    const comment = document.getElementById('shareComment').value.trim();
    const editName = document.getElementById('shareNameEdit').value;

    if (!name || !path) {
        showToast('Заполните имя и путь', 'warning');
        return;
    }

    if (!/^[a-zA-Z0-9_\-.]+$/.test(name)) {
        showToast('Имя содержит недопустимые символы', 'warning');
        return;
    }

    const data = { name, path, read_only, guest_ok, valid_users, comment };
    const url = editName ? `/api/shares/${encodeURIComponent(editName)}` : '/api/shares';
    const method = editName ? 'PUT' : 'POST';

    fetch(url, {
        method: method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    })
    .then(r => r.json())
    .then(result => {
        if (result.error) {
            showToast('Ошибка: ' + result.error, 'danger');
        } else {
            showToast(result.message || 'Сохранено', 'success');
            closeModal('shareModal');
            loadShares();
        }
    })
    .catch(err => {
        showToast('Ошибка сети: ' + err.message, 'danger');
    });
}

// ============ УДАЛЕНИЕ ============
function deleteShare(name) {
    if (!confirm(`Удалить шару "${name}"?`)) return;

    fetch(`/api/shares/${encodeURIComponent(name)}`, { method: 'DELETE' })
        .then(r => r.json())
        .then(result => {
            if (result.error) {
                showToast('Ошибка: ' + result.error, 'danger');
            } else {
                showToast(result.message || 'Шара удалена', 'success');
                loadShares();
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
document.addEventListener('DOMContentLoaded', loadShares);

// Экспорт
window.loadShares = loadShares;
window.showAddShare = showAddShare;
window.editShare = editShare;
window.saveShare = saveShare;
window.deleteShare = deleteShare;
