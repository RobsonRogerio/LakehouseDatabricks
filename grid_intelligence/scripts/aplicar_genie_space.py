#!/usr/bin/env python3
"""Cria ou atualiza o Genie space do Grid Intelligence a partir de src/genie/grid_genie_space.json.

Genie space nao e recurso de bundle: este script substitui ${catalogo} no JSON versionado
e aplica via CLI, para nao depender de configuracao manual pela UI.

Uso:
  python scripts/aplicar_genie_space.py <catalogo> --profile grid_intelligence [--warehouse-id ID]
"""
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

TITLE = "Grid Intelligence - Copiloto de Operacoes"
DESCRIPTION = (
    "Copiloto conversacional da Luz do Vale Distribuidora S.A. Responde em portugues "
    "sobre continuidade de fornecimento (DEC/FEC), operacao do dia, prioridade de "
    "inspecao e risco de ouvidoria, a partir apenas da camada gold (RN-13)."
)
SPACE_JSON_PATH = Path(__file__).resolve().parent.parent / "src" / "genie" / "grid_genie_space.json"
DEFAULT_WAREHOUSE_ID = "7601ed0c547d89aa"


def run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Comando falhou: {' '.join(cmd)}", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return result.stdout


def find_existing_space_id(profile: str) -> str | None:
    out = run(["databricks", "genie", "list-spaces", "--profile", profile, "--output", "json"])
    data = json.loads(out)
    for space in data.get("spaces", []):
        if space.get("title") == TITLE:
            return space["space_id"]
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("catalogo", help="Nome do catalogo (ex.: grid_dev, grid_intelligence)")
    parser.add_argument("--profile", default="grid_intelligence")
    parser.add_argument("--warehouse-id", default=DEFAULT_WAREHOUSE_ID)
    parser.add_argument("--parent-path", default=None, help="Default: /Users/<usuario atual>")
    args = parser.parse_args()

    raw = SPACE_JSON_PATH.read_text(encoding="utf-8")
    substituted = raw.replace("${catalogo}", args.catalogo)
    serialized_space = json.loads(substituted)  # valida antes de aplicar

    parent_path = args.parent_path
    if parent_path is None:
        who = json.loads(run(["databricks", "current-user", "me", "--profile", args.profile]))
        parent_path = f"/Users/{who['userName']}"

    space_id = find_existing_space_id(args.profile)

    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        if space_id is None:
            payload = {
                "warehouse_id": args.warehouse_id,
                "title": TITLE,
                "description": DESCRIPTION,
                "parent_path": parent_path,
                "serialized_space": json.dumps(serialized_space),
            }
        else:
            payload = {"serialized_space": json.dumps(serialized_space)}
        json.dump(payload, f)
        payload_path = f.name

    if space_id is None:
        print(f"Criando Genie space '{TITLE}' com catalogo={args.catalogo}...")
        out = run([
            "databricks", "genie", "create-space",
            "--json", f"@{payload_path}",
            "--profile", args.profile,
            "--output", "json",
        ])
        result = json.loads(out)
        space_id = result["space_id"]
        print(f"Space criado: {space_id}")
    else:
        print(f"Atualizando Genie space existente ({space_id}) com catalogo={args.catalogo}...")
        run([
            "databricks", "genie", "update-space", space_id,
            "--json", f"@{payload_path}",
            "--profile", args.profile,
        ])
        print(f"Space atualizado: {space_id}")

    print(space_id)


if __name__ == "__main__":
    main()
