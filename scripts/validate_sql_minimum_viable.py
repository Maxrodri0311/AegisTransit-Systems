"""
scripts/validate_sql_minimum_viable.py
CI/CD Guard: Valida que el código SQL represente al menos el 25% del total de bytes
del repositorio para asegurar su visibilidad como lenguaje primario en GitHub Linguist.
"""

import os
from pathlib import Path
import json
import sys

EXTENSION_MAP = {
    ".py": "Python",
    ".sql": "SQL",
    ".tf": "HCL",
    ".ts": "TypeScript",
    ".js": "JavaScript",
}

IGNORED_EXTS = {
    ".bat", ".cmd", ".ps1", ".sh", ".parquet", ".csv",
    ".json", ".yaml", ".yml", ".md", ".txt", ".ini",
    ".toml", ".ico", ".lock", ".pyc"
}

IGNORED_DIRS = {".git", ".pytest_cache", "__pycache__", "venv", ".venv", "dist", "build"}


def main():
    root = Path(".").resolve()
    
    # 1. Determinar si SQL es requerido
    has_sql_requirement = False
    manifest_path = root / "scaffolding.manifest.json"
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            stack = manifest.get("complementary_stack", []) + manifest.get("stack", [])
            has_sql_requirement = any("sql" in s.lower() or "postgres" in s.lower() for s in stack)
        except Exception:
            pass

    sql_files = list(root.glob("analytics/queries/*.sql")) + list(root.glob("**/*.sql"))
    if not has_sql_requirement and not sql_files:
        print("[SQL Guard PASS] SQL no requerido en este proyecto. Omitiendo validación.")
        sys.exit(0)

    # 2. Calcular bytes reales
    lang_bytes = {}
    total_bytes = 0

    for r, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in IGNORED_DIRS]
        for f in files:
            fp = Path(r) / f
            ext = fp.suffix.lower()
            if ext in IGNORED_EXTS or ext not in EXTENSION_MAP:
                continue
            sz = fp.stat().st_size
            lang = EXTENSION_MAP[ext]
            lang_bytes[lang] = lang_bytes.get(lang, 0) + sz
            total_bytes += sz

    if total_bytes == 0:
        print("[SQL Guard FAIL] Repositorio sin código fuente detectable.")
        sys.exit(1)

    sql_b = lang_bytes.get("SQL", 0)
    ratio = sql_b / total_bytes

    print(f"[SQL Guard] Total Bytes: {total_bytes:,} | SQL Bytes: {sql_b:,} ({ratio*100:.1f}%)")

    if ratio < 0.25:
        print(f"[SQL Guard FAIL] SQL debe ser >=25% para ser visible en Linguist (actual: {ratio*100:.1f}%).")
        sys.exit(1)

    print(f"[SQL Guard PASS] SQL cumple con el mínimo viable de Linguist ({ratio*100:.1f}% >= 25%).")
    sys.exit(0)


if __name__ == "__main__":
    main()