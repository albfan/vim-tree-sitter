#!/usr/bin/env python3
"""
ts_helper.py - small CLI helper that uses tree_sitter Python bindings.

Usage:
  python3 ts_helper.py --lang python ast
  python3 ts_helper.py --lang python node_at ROW COL
  python3 ts_helper.py --lang python symbols
  python3 ts_helper.py --lang python folds

Behavior:
- Loads pip-installed language package named tree_sitter_<lang> and calls its language().
- Creates Parser(lang) when available, otherwise falls back to Parser() + set_language().
- Commands:
  - ast      : prints a nested AST (nodes with children and text)
  - node_at  : prints the single smallest named node at ROW COL (0-based)
  - symbols  : prints a list of symbol nodes (heuristic) with optional name
  - folds    : prints a flat list of nodes that span multiple lines (type + start/end)
"""
from __future__ import annotations
import sys
import argparse
import json
import importlib
from typing import Optional

try:
    from tree_sitter import Language, Parser
except Exception:
    sys.stderr.write("Missing tree_sitter Python package: pip install tree-sitter\n")
    sys.exit(2)


# Conservative symbol and fold defaults (can be refined by editor using per-language rules)
DEFAULT_SYMBOL_NODE_TYPES = set([
    "function_definition", "function_declaration", "function_item",
    "method_definition", "method_declaration", "class_declaration",
    "class_definition", "class_specifier", "function", "method",
])

def load_language_from_package(lang_name: str):
    mod_name = f"tree_sitter_{lang_name}"
    try:
        mod = importlib.import_module(mod_name)
    except Exception as e:
        raise RuntimeError(
            f"Could not import language package '{mod_name}'. Install it with: pip install {mod_name.replace('_', '-')}\nUnderlying error: {e}"
        )
    lang_fn = getattr(mod, "language", None)
    if not callable(lang_fn):
        raise RuntimeError(f"Module {mod_name} does not expose language()")
    lang_obj = lang_fn()
    # If it already returns a tree_sitter.Language, return it directly
    if isinstance(lang_obj, Language):
        return lang_obj
    # Otherwise, try wrapping with Language() (some packages export raw compiled language)
    try:
        return Language(lang_obj)
    except Exception:
        # last resort: return whatever the package returned (Parser constructor may accept it)
        return lang_obj


def load_language(lang_name: str):
    return load_language_from_package(lang_name)


def make_parser_for_language(lang):
    # Try Parser(lang) first, otherwise Parser() + set_language(lang)
    try:
        return Parser(lang)
    except TypeError:
        p = Parser()
        p.set_language(lang)
        return p
    except Exception:
        # last attempt
        p = Parser()
        p.set_language(lang)
        return p


def node_to_dict(node, source_bytes: bytes, include_text: bool = False, max_text: int = 120):
    # Some nodes may lack start_point / end_point; guard accordingly
    try:
        srow, scol = node.start_point
        erow, ecol = node.end_point
    except Exception:
        srow = scol = erow = ecol = 0
    d = {
        "type": getattr(node, "type", None),
        "named": getattr(node, "is_named", False),
        "start_point": [srow, scol],
        "end_point": [erow, ecol],
        "start_byte": getattr(node, "start_byte", 0),
        "end_byte": getattr(node, "end_byte", 0),
    }
    if include_text:
        try:
            text = source_bytes[d["start_byte"]:d["end_byte"]].decode("utf8", "replace")
            text = " ".join(text.split())
            if len(text) > max_text:
                text = text[:max_text - 3] + "..."
            d["text"] = text
        except Exception:
            d["text"] = ""
    return d


def walk_node(node, source_bytes: bytes):
    d = node_to_dict(node, source_bytes, include_text=True)
    children = []
    for child in getattr(node, "children", []):
        children.append(walk_node(child, source_bytes))
    d["children"] = children
    return d


def find_smallest_named_at(root, row: int, col: int):
    try:
        return root.named_descendant_for_point_range((row, col), (row, col))
    except Exception:
        return None


def collect_symbols(root, symbol_types: Optional[set] = None):
    if symbol_types is None:
        symbol_types = DEFAULT_SYMBOL_NODE_TYPES
    out = []

    def visit(n):
        ntype = getattr(n, "type", None)
        if ntype in symbol_types:
            out.append(n)
        for c in getattr(n, "children", []):
            visit(c)

    visit(root)
    out.sort(key=lambda n: (n.start_point[0], n.start_point[1]))
    return out


def collect_folds(root):
    """
    Return a flat list of nodes that span multiple lines. Each item is a dict:
      { type, start_point, end_point, start_byte, end_byte }
    This is a lightweight list used by the editor to compute fold levels.
    """
    out = []

    def visit(n):
        try:
            sp = n.start_point[0]
            ep = n.end_point[0]
        except Exception:
            return
        if ep > sp:
            out.append(n)
        for c in getattr(n, "children", []):
            visit(c)

    visit(root)
    out.sort(key=lambda n: (n.start_point[0], n.start_point[1]))
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--lang', required=True, help='Language name (e.g. python, javascript)')
    p.add_argument('cmd', choices=['ast', 'node_at', 'symbols', 'folds'])
    p.add_argument('args', nargs='*')
    args = p.parse_args()

    try:
        lang = load_language(args.lang)
    except Exception as e:
        sys.stderr.write(f"Error loading language: {e}\n")
        sys.exit(4)

    try:
        parser = make_parser_for_language(lang)
    except Exception as e:
        sys.stderr.write(f"Failed to construct parser: {e}\n")
        sys.exit(5)

    try:
        source_bytes = sys.stdin.buffer.read() or b""
    except Exception:
        source_bytes = b""

    # Allow empty input gracefully
    try:
        tree = parser.parse(source_bytes)
        root = tree.root_node
    except Exception as e:
        # If parse fails, return sensible empty results
        root = None

    if args.cmd == "ast":
        if not root:
            print(json.dumps({}))
            return
        ast = walk_node(root, source_bytes)
        print(json.dumps(ast))
        return

    if args.cmd == "node_at":
        if len(args.args) < 2:
            sys.stderr.write("node_at requires ROW COL\n")
            sys.exit(7)
        try:
            row = int(args.args[0])
            col = int(args.args[1])
        except Exception:
            sys.stderr.write("Invalid ROW/COL\n")
            sys.exit(8)
        if not root:
            print(json.dumps({}))
            return
        node = find_smallest_named_at(root, row, col)
        if node is None:
            print(json.dumps({}))
            return
        d = node_to_dict(node, source_bytes, include_text=True)
        d["children_count"] = len(getattr(node, "children", []))
        print(json.dumps(d))
        return

    if args.cmd == "symbols":
        if not root:
            print(json.dumps([]))
            return
        syms = collect_symbols(root)
        out = []
        for n in syms:
            name = None
            for c in getattr(n, "children", []):
                ctype = getattr(c, "type", "")
                if 'name' in ctype or 'identifier' in ctype or ctype == 'identifier':
                    try:
                        name = source_bytes[c.start_byte:c.end_byte].decode('utf8', 'replace')
                        name = " ".join(name.split())
                        break
                    except Exception:
                        name = None
            d = node_to_dict(n, source_bytes, include_text=False)
            d['name'] = name
            out.append(d)
        print(json.dumps(out))
        return

    if args.cmd == "folds":
        if not root:
            print(json.dumps([]))
            return
        nodes = collect_folds(root)
        out = []
        for n in nodes:
            d = {
                "type": getattr(n, "type", None),
                "start_point": [n.start_point[0], n.start_point[1]],
                "end_point": [n.end_point[0], n.end_point[1]],
                "start_byte": getattr(n, "start_byte", 0),
                "end_byte": getattr(n, "end_byte", 0),
            }
            out.append(d)
        print(json.dumps(out))
        return


if __name__ == "__main__":
    main()
