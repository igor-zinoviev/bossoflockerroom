"""Адаптер для avr.org.ua (Архів визвольного руху, Центр досліджень визвольного руху).

Публічний API віддає каталог документів сторінками (skip/limit). Замість десятків «зондувальних» запитів
каталог (~37 тис. записів, ~30 МБ) завантажується ОДИН раз із паузами та кешується, а пошук іде локально.
Формат спостережений у 2026-10 і може змінитися.
"""
from __future__ import annotations

import re

from .fetch import Fetcher

API = "https://avr.org.ua/api/getdocums/ua"
PAGE = 1000


def fetch_page(f: Fetcher, skip: int, limit: int = PAGE):
    payload = {"filter": {"shownodates": False, "filterdates": False}, "skip": skip, "limit": limit}
    d = f.get_json(API, data=payload)
    return d[0]["info"][0]["count"], d[0]["rows"]


def fetch_index(f: Fetcher, max_pages: int | None = None):
    total, rows = fetch_page(f, 0)
    pages = (total + PAGE - 1) // PAGE
    for p in range(1, min(pages, max_pages or pages)):
        rows += fetch_page(f, p * PAGE)[1]
    return rows


def search_local(rows, pattern: str, fields=("NAME", "STEXT")):
    rx = re.compile(pattern, re.I)
    seen, out = set(), []
    for r in rows:  # каталог містить дублікати одного ID (приєднані довідники)
        if r["ID"] not in seen and any(rx.search(r.get(k) or "") for k in fields):
            seen.add(r["ID"])
            out.append(r)
    return out


def brief(r) -> str:
    return f'#{r["ID"]} {r["NAME"][:90]} | {(r.get("CRDATA") or "")} | {(r.get("STEXT") or "")[:140]}'
