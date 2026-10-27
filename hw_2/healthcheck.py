"""Проверка без curl/wget в runtime-образе."""

import os
from urllib.request import urlopen


with urlopen(f"http://127.0.0.1:{os.environ.get('APP_PORT', '8080')}/health", timeout=4) as response:
    if response.status != 200:
        raise SystemExit(1)
