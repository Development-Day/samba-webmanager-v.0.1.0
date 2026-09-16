// ============================================================
// Samba Web Manager - общие функции
// ============================================================

// ============ ФОРМАТИРОВАНИЕ ============
function formatBytes(bytes, decimals = 1) {
    if (bytes === 0 || !bytes) return '0 B';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

function generatePassword(length = 12) {
    const charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()';
    let password = '';
    for (let i = 0; i < length; i++) {
        password += charset.charAt(Math.floor(Math.random() * charset.length));
    }
    return password;
}

function isValidIP(ip) {
    const pattern = /^(\d{1,3}\.){3}\d{1,3}$/;
    if (!pattern.test(ip)) return false;
    return ip.split('.').every(num => {
        const n = parseInt(num);
        return n >= 0 && n <= 255;
    });
}

// ============ СВОИ МОДАЛЬНЫЕ ОКНА ============
function openModal(id) {
    const modal = document.getElementById(id);
    if (modal) {
        modal.classList.add('active');
        document.body.style.overflow = 'hidden';
    }
}

function closeModal(id) {
    const modal = document.getElementById(id);
    if (modal) {
        modal.classList.remove('active');
        document.body.style.overflow = '';
    }
}

document.addEventListener('click', function(e) {
    if (e.target.classList.contains('modal-overlay')) {
        e.target.classList.remove('active');
        document.body.style.overflow = '';
    }
});

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        document.querySelectorAll('.modal-overlay.active').forEach(m => {
            m.classList.remove('active');
            document.body.style.overflow = '';
        });
    }
});

// ============ УВЕДОМЛЕНИЯ ============
function showToast(message, type = 'success') {
    const colors = {
        success: { bg: '#001a00', border: '#00ff66', text: '#00ff66' },
        danger:  { bg: '#1a0000', border: '#ff0033', text: '#ff0033' },
        warning: { bg: '#1a1000', border: '#ffaa00', text: '#ffaa00' },
        info:    { bg: '#001a1a', border: '#00ffff', text: '#00ffff' }
    };
    const c = colors[type] || colors.info;

    const toast = document.createElement('div');
    toast.style.cssText = `
        position: fixed;
        bottom: 25px;
        right: 25px;
        background: ${c.bg};
        color: ${c.text};
        border: 2px solid ${c.border};
        padding: 15px 25px;
        font-family: "Consolas", "Courier New", monospace;
        font-size: 12px;
        font-weight: bold;
        letter-spacing: 1px;
        text-shadow: 0 0 10px ${c.border};
        box-shadow: 0 0 25px ${c.border}40, inset 0 0 20px ${c.border}10;
        z-index: 9999;
        max-width: 400px;
        animation: slideInToast 0.3s ease;
    `;
    toast.textContent = message;
    document.body.appendChild(toast);

    setTimeout(() => {
        toast.style.transition = 'opacity 0.3s, transform 0.3s';
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(20px)';
        setTimeout(() => toast.remove(), 300);
    }, 4000);
}

const toastStyle = document.createElement('style');
toastStyle.textContent = `
    @keyframes slideInToast {
        from { transform: translateX(100%); opacity: 0; }
        to { transform: translateX(0); opacity: 1; }
    }
`;
document.head.appendChild(toastStyle);

// ============ АВТООБНОВЛЕНИЕ ============
let autoRefreshInterval = null;

function startAutoRefresh(interval = 30000) {
    if (autoRefreshInterval) clearInterval(autoRefreshInterval);
    autoRefreshInterval = setInterval(() => {
        if (!document.hidden) location.reload();
    }, interval);
}

function stopAutoRefresh() {
    if (autoRefreshInterval) {
        clearInterval(autoRefreshInterval);
        autoRefreshInterval = null;
    }
}

// ============ FETCH С ОБРАБОТКОЙ ============
async function fetchWithError(url, options = {}) {
    try {
        const response = await fetch(url, {
            ...options,
            headers: {
                'Content-Type': 'application/json',
                ...(options.headers || {})
            }
        });
        const data = await response.json();
        if (!response.ok) {
            throw new Error(data.error || `HTTP ${response.status}`);
        }
        return data;
    } catch (error) {
        showToast(`Ошибка: ${error.message}`, 'danger');
        throw error;
    }
}

// ============ ЭКСПОРТ ============
window.formatBytes = formatBytes;
window.generatePassword = generatePassword;
window.isValidIP = isValidIP;
window.openModal = openModal;
window.closeModal = closeModal;
window.showToast = showToast;
window.startAutoRefresh = startAutoRefresh;
window.stopAutoRefresh = stopAutoRefresh;
window.fetchWithError = fetchWithError;
