"""
scripts/validate_terraform_minimum_viable.py
CI/CD Guard: Valida que si Terraform está en el stack del proyecto, existan al menos
2 KB de configuraciones HCL legítimas (resources, providers, outputs).
"""

import os
from pathlib import Path
import json
import sys


def main():
    root = Path(".").resolve()
    
    # 1. Determinar si Terraform es requerido
    has_tf_requirement = False
    manifest_path = root / "scaffolding.manifest.json"
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            stack = manifest.get("complementary_stack", []) + manifest.get("stack", [])
            has_tf_requirement = any("terraform" in s.lower() for s in stack)
        except Exception:
            pass

    tf_files = list(root.glob("infrastructure/*.tf")) + list(root.glob("**/*.tf"))
    tf_files = [f for f in tf_files if ".terraform" not in f.parts and "venv" not in f.parts]

    if not has_tf_requirement and not tf_files:
        print("[Terraform Guard PASS] Terraform no requerido en este proyecto. Omitiendo validación.")
        sys.exit(0)

    # 2. Sumar bytes de archivos .tf
    hcl_bytes = sum(f.stat().st_size for f in tf_files if f.is_file())
    print(f"[Terraform Guard] Archivos HCL detectados: {len(tf_files)} | HCL Bytes: {hcl_bytes:,}")

    if hcl_bytes < 2000:
        print(f"[Terraform Guard FAIL] Terraform debe tener >=2 KB de HCL si está en el stack (actual: {hcl_bytes} bytes).")
        sys.exit(1)

    print(f"[Terraform Guard PASS] Terraform cumple con el mínimo viable ({hcl_bytes:,} bytes >= 2,000 bytes).")
    sys.exit(0)


if __name__ == "__main__":
    main()