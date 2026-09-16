import pytest
import os
import tempfile
from samba_manager import config_parser

def test_config_parser():
    """Тест парсера конфигурации"""
    # Создаем временный конфиг
    with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
        f.write("""
[global]
workgroup = WORKGROUP

[test_share]
path = /tmp/test
read only = no
guest ok = yes
""")
        temp_path = f.name
    
    try:
        config = config_parser.SambaConfig(temp_path)
        shares = config.get_shares()
        assert len(shares) == 1
        assert shares[0]['name'] == 'test_share'
        assert shares[0]['path'] == '/tmp/test'
        assert shares[0]['read_only'] == False
    finally:
        os.unlink(temp_path)

def test_add_share():
    """Тест добавления шары"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
        f.write("[global]\nworkgroup = WORKGROUP\n")
        temp_path = f.name
    
    try:
        config = config_parser.SambaConfig(temp_path)
        config.add_share('new_share', '/tmp/new', read_only=True, guest_ok=False)
        
        shares = config.get_shares()
        assert len(shares) == 1
        assert shares[0]['name'] == 'new_share'
        assert shares[0]['path'] == '/tmp/new'
        assert shares[0]['read_only'] == True
        assert shares[0]['guest_ok'] == False
    finally:
        os.unlink(temp_path)