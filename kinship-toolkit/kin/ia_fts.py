"""Повнотекстовий пошук Internet Archive (серед іншого — оцифровані галицькі газети, шематизми, довідники).

Економія токенів: спершу короткі сніпети (search), повний OCR — лише для відібраних ідентифікаторів (text_for),
і з нього витягуються тільки вікна навколо ключового слова (contexts).
"""
from __future__ import annotations

import json
import re
import urllib.parse
from dataclasses import dataclass

from .fetch import Fetcher

FTS = ("https://archive.org/services/search/beta/page_production/?service_backend=fts&user_query={q}"
       "&hits_per_page={n}&page={page}&aggregations=false")
MAX_OCR_BYTES = 15_000_000


@dataclass
class Hit:
    ident: str
    title: str
    snippet: str


def search(f: Fetcher, query: str, n: int = 20, page: int = 1, snip: int = 260):
    """Повертає (total, [Hit]). Запит — рівень сторінки, оператор AND між словами."""
    url = FTS.format(q=urllib.parse.quote(query), n=n, page=page)
    d = json.loads(f.get(url))
    hits = d.get("response", {}).get("body", {}).get("hits", {})
    out = []
    for h in hits.get("hits", []):
        fl = h.get("fields", {})
        hl = h.get("highlight", {}).get("text", [])
        out.append(Hit(fl.get("identifier", ""), (fl.get("title") or "")[:100], re.sub(r"\s+", " ", hl[0])[:snip] if hl else ""))
    return hits.get("total"), out


def text_for(f: Fetcher, ident: str) -> str:
    """OCR-текст документа (кешується). Дуже великі файли пропускаються."""
    meta = json.loads(f.get("https://archive.org/metadata/" + urllib.parse.quote(ident)))
    files = meta.get("files", [])
    t = next((x for x in files if x["name"].endswith("_djvu.txt")), None)
    if not t or int(t.get("size", 0)) > MAX_OCR_BYTES:
        return ""
    url = "https://archive.org/download/%s/%s" % (urllib.parse.quote(ident), urllib.parse.quote(t["name"]))
    return f.get(url).decode("utf-8", "replace")


def contexts(text: str, key_re: str, near_re: str | None = None, width: int = 300, maxn: int = 4) -> list[str]:
    out = []
    for m in re.finditer(key_re, text, re.I):
        win = text[max(0, m.start() - width): m.end() + width]
        if near_re is None or re.search(near_re, win, re.I):
            out.append(re.sub(r"\s+", " ", win))
            if len(out) >= maxn:
                break
    return out


def sweep(f: Fetcher, query: str, key_re: str, near_re: str | None = None, pages: int = 2, per: int = 50):
    """Збирає ідентифікатори за запитом, тягне OCR і повертає {ident: [контексти]} лише де щось знайдено."""
    idents: dict[str, str] = {}
    for p in range(1, pages + 1):
        total, hits = search(f, query, n=per, page=p)
        for h in hits:
            idents[h.ident] = h.title
        if not hits or len(idents) >= (total or 0):
            break
    found = {}
    for ident, title in idents.items():
        try:
            ctx = contexts(text_for(f, ident), key_re, near_re)
        except Exception:
            continue
        if ctx:
            found[ident] = {"title": title, "contexts": ctx}
    return found
