"""
Omni Adapter Registry — apps self-register via adapters.d/ manifests.

This module replaces omni's Layer 3 (local ~/.local/share scan) with a proper
registry pattern. Apps drop JSON manifests into adapters.d/ on first launch.
Omni reads them to discover adapters.

To integrate into omni:
1. Copy this file to eidosomni/src/omni/adapters/registry.py
2. Update adapters/__init__.py to call AdapterRegistry.load_registered_adapters()
   in place of the current Layer 3 local scan

Standalone reference implementation — can be tested without omni running.
"""

import importlib.util
import json
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

ADAPTERS_D = Path("~/.config/eidosomni/adapters.d").expanduser()


@dataclass
class RegisteredAdapter:
    """An adapter discovered from a manifest in adapters.d/."""
    name: str
    manifest: dict[str, Any]
    adapter_path: Path
    module: Any = None  # The loaded Python module
    adapter_class: Any = None  # The AdapterBase subclass
    load_error: str | None = None
    stale: bool = False


def discover_registered_adapters() -> list[RegisteredAdapter]:
    """Read adapters.d/*.json manifests and load adapter modules.

    Returns list of RegisteredAdapter records. Adapters with errors
    are included with load_error set (not silently dropped).
    """
    records: list[RegisteredAdapter] = []

    if not ADAPTERS_D.exists():
        return records

    for manifest_path in sorted(ADAPTERS_D.glob("*.json")):
        try:
            manifest = json.loads(manifest_path.read_text())
        except (json.JSONDecodeError, OSError) as e:
            logger.warning(f"Bad manifest {manifest_path.name}: {e}")
            continue

        name = manifest.get("name", manifest_path.stem)
        adapter_info = manifest.get("adapter", {})
        code_path = Path(adapter_info.get("path", "")).expanduser()

        # Health check: does the adapter code exist?
        if not code_path.exists():
            records.append(RegisteredAdapter(
                name=name,
                manifest=manifest,
                adapter_path=code_path,
                stale=True,
                load_error=f"Adapter path not found: {code_path}",
            ))
            logger.info(f"Stale adapter '{name}': {code_path} not found")
            continue

        # Dynamic import
        try:
            spec = importlib.util.spec_from_file_location(
                f"omni_adapter_{name}", code_path
            )
            if spec is None or spec.loader is None:
                raise ImportError(f"Cannot create module spec for {code_path}")

            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)

            # Find the AdapterBase subclass
            adapter_class = None
            for attr_name in dir(module):
                obj = getattr(module, attr_name)
                if (
                    isinstance(obj, type)
                    and hasattr(obj, "name")
                    and hasattr(obj, "sync")
                    and hasattr(obj, "read_content")
                    and obj.__module__ == module.__name__
                ):
                    adapter_class = obj
                    break

            if adapter_class is None:
                raise ImportError(f"No adapter class found in {code_path}")

            records.append(RegisteredAdapter(
                name=name,
                manifest=manifest,
                adapter_path=code_path,
                module=module,
                adapter_class=adapter_class,
            ))
            logger.info(
                f"Loaded registered adapter '{name}' "
                f"v{manifest.get('version', '?')} "
                f"from {manifest.get('registered_by', 'unknown')}"
            )

        except Exception as e:
            records.append(RegisteredAdapter(
                name=name,
                manifest=manifest,
                adapter_path=code_path,
                load_error=str(e),
            ))
            logger.error(f"Failed to load adapter '{name}': {e}")

    return records


def list_registered() -> list[dict]:
    """Human-readable list of registered adapters (for CLI/MCP tools)."""
    if not ADAPTERS_D.exists():
        return []

    results = []
    for manifest_path in sorted(ADAPTERS_D.glob("*.json")):
        try:
            m = json.loads(manifest_path.read_text())
            code_path = Path(m.get("adapter", {}).get("path", "")).expanduser()
            results.append({
                "name": m.get("name", manifest_path.stem),
                "version": m.get("version", "?"),
                "registered_by": m.get("registered_by", "?"),
                "adapter_path": str(code_path),
                "exists": code_path.exists(),
                "data_dir": m.get("data_dir", "?"),
                "uri_scheme": m.get("uri_scheme", "?"),
            })
        except Exception:
            continue

    return results


# ── CLI for testing ──────────────────────────────────────────────

if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "--list":
        for r in list_registered():
            status = "OK" if r["exists"] else "STALE"
            print(f"  [{status}] {r['name']} v{r['version']} — {r['registered_by']}")
            print(f"         adapter: {r['adapter_path']}")
            print(f"         data:    {r['data_dir']}")
            print()
    else:
        records = discover_registered_adapters()
        print(f"Discovered {len(records)} registered adapter(s):")
        for r in records:
            if r.load_error:
                print(f"  [ERR]   {r.name}: {r.load_error}")
            elif r.stale:
                print(f"  [STALE] {r.name}: {r.adapter_path}")
            else:
                print(f"  [OK]    {r.name}: {r.adapter_class}")
