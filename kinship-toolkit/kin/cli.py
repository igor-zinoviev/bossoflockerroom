"""Командний рядок: python -m kin <команда>. Вивід навмисно короткий (економія токенів)."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import avr, gedcom, graph, ia_fts
from .fetch import Fetcher, HostBlocked


def cmd_validate(a):
    persons, rels = graph.load_registers(a.case)
    issues = graph.validate(persons, rels)
    for i in issues:
        print(i)
    print("ПІДСУМОК:", graph.summarize(issues), f"| осіб={len(persons)}, зв'язків={len(rels)}")
    return 1 if any(i.severity == "ERROR" for i in issues) else 0


def cmd_gedcom(a):
    persons, rels = graph.load_registers(a.case)
    text = gedcom.export(persons, rels, redact_living=not a.show_living)
    errs = gedcom.validate_gedcom(text)
    Path(a.out).write_text(text, encoding="utf-8")
    print(f"записано {a.out}: рядків={len(text.splitlines())}; проблем структури={len(errs)}")
    for e in errs:
        print(" -", e)
    print(gedcom.validate_with_python_gedcom(a.out))
    return 1 if errs else 0


def cmd_ia(a):
    f = Fetcher(cache_dir=a.cache, min_interval=1.5)
    if a.key:
        found = ia_fts.sweep(f, a.query, a.key, a.near, pages=a.pages)
        for ident, v in found.items():
            print(f"- {ident} | {v['title']}")
            for c in v["contexts"][:2]:
                print("    …", c[:400])
        print(f"ПІДСУМОК: документів із контекстами={len(found)}; {f.stats}")
    else:
        total, hits = ia_fts.search(f, a.query, n=a.n)
        print("всього:", total)
        for h in hits:
            print(f"- {h.ident} | {h.title} | {h.snippet}")
    return 0


def cmd_avr(a):
    f = Fetcher(cache_dir=a.cache, min_interval=1.0)
    idx = Path(a.cache) / "avr_index.json"
    if idx.exists():
        rows = json.loads(idx.read_text(encoding="utf-8"))
    else:
        rows = avr.fetch_index(f)
        idx.write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
    hits = avr.search_local(rows, a.pattern)
    for r in hits[: a.n]:
        print(avr.brief(r)[:260])
    print(f"ПІДСУМОК: {len(hits)} збігів у каталозі з {len(rows)} записів; {f.stats}")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="kin", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("validate", help="перевірка дерева: цикли, вік батьків, тезки, сила доказів")
    p.add_argument("case")
    p.set_defaults(fn=cmd_validate)
    p = sub.add_parser("gedcom", help="експорт і перевірка GEDCOM")
    p.add_argument("case")
    p.add_argument("out")
    p.add_argument("--show-living", action="store_true", help="НЕ ховати живих (лише для приватного використання)")
    p.set_defaults(fn=cmd_gedcom)
    p = sub.add_parser("ia", help="повнотекстовий пошук Internet Archive")
    p.add_argument("query")
    p.add_argument("--key", help="regex ключового слова: тягнути OCR і показувати контексти")
    p.add_argument("--near", help="regex, що має бути поруч")
    p.add_argument("--pages", type=int, default=2)
    p.add_argument("-n", type=int, default=15)
    p.add_argument("--cache", default=".kin-cache")
    p.set_defaults(fn=cmd_ia)
    p = sub.add_parser("avr", help="локальний пошук по каталогу avr.org.ua (завантажується один раз)")
    p.add_argument("pattern")
    p.add_argument("-n", type=int, default=15)
    p.add_argument("--cache", default=".kin-cache")
    p.set_defaults(fn=cmd_avr)
    a = ap.parse_args(argv)
    Path(getattr(a, "cache", ".")).mkdir(parents=True, exist_ok=True)
    try:
        return a.fn(a)
    except HostBlocked as e:
        print("ЗАБЛОКОВАНО (зафіксуйте у search-log, не обходьте):", e)
        return 2


if __name__ == "__main__":
    sys.exit(main())
