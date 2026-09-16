import os
import gzip
import datetime
import shutil
from typing import List, Dict

BACKUP_DIR = 'backups'
SAMBA_CONFIG = '/etc/samba/smb.conf'

def ensure_backup_dir():
    if not os.path.exists(BACKUP_DIR):
        os.makedirs(BACKUP_DIR)

def create_backup() -> str:
    ensure_backup_dir()
    
    timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_file = os.path.join(BACKUP_DIR, f'smb.conf_{timestamp}.gz')
    
    with open(SAMBA_CONFIG, 'r') as f:
        content = f.read()
    
    with gzip.open(backup_file, 'wt', encoding='utf-8') as f:
        f.write(content)
    
    cleanup_old_backups()
    return backup_file

def restore_backup(filename: str):
    backup_path = os.path.join(BACKUP_DIR, filename)
    if not os.path.exists(backup_path):
        raise FileNotFoundError(f'Бэкап {filename} не найден')
    
    create_backup()
    
    with gzip.open(backup_path, 'rt', encoding='utf-8') as f:
        content = f.read()
    
    with open(SAMBA_CONFIG, 'w') as f:
        f.write(content)

def list_backups() -> List[Dict]:
    ensure_backup_dir()
    backups = []
    
    for filename in os.listdir(BACKUP_DIR):
        if filename.startswith('smb.conf_') and filename.endswith('.gz'):
            filepath = os.path.join(BACKUP_DIR, filename)
            size = os.path.getsize(filepath)
            mtime = os.path.getmtime(filepath)
            
            try:
                timestamp = filename.replace('smb.conf_', '').replace('.gz', '')
                date = datetime.datetime.strptime(timestamp, '%Y%m%d_%H%M%S')
            except:
                date = datetime.datetime.fromtimestamp(mtime)
            
            backups.append({
                'filename': filename,
                'date': date.isoformat(),
                'size': size,
                'size_human': format_size(size)
            })
    
    backups.sort(key=lambda x: x['date'], reverse=True)
    return backups

def delete_backup(filename: str):
    filepath = os.path.join(BACKUP_DIR, filename)
    if os.path.exists(filepath):
        os.remove(filepath)

def cleanup_old_backups(max_count: int = 10):
    backups = list_backups()
    if len(backups) > max_count:
        for backup in backups[max_count:]:
            delete_backup(backup['filename'])

def format_size(size: int) -> str:
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size < 1024.0:
            return f"{size:.1f} {unit}"
        size /= 1024.0
    return f"{size:.1f} TB"