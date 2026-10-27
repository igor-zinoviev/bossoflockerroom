"""Ввічливий HTTP-клієнт: кеш на диску, ліміт частоти на хост, повтори з паузою, «вимикач» при відмові.

Що він НЕ робить (свідомо): не ротує проксі, не підміняє особистість клієнта, не обходить CAPTCHA/403/429.
Якщо сайт відмовляє (403/429 кілька разів поспіль) — хост позначається як заблокований, і помилка
повертається викликачеві, щоб зафіксувати блокування у search-log, а не «пробивати» його.
"""
from __future__ import annotations

import hashlib
import json
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

UA = "kinship-toolkit/0.1 (personal genealogy research; polite client)"


class HostBlocked(RuntimeError):
    """Хост відмовив кілька разів поспіль; подальші запити припинено."""


class Fetcher:
    def __init__(self, cache_dir: str | Path | None = None, min_interval: float = 1.0, retries: int = 3,
                 block_after: int = 3, timeout: float = 90, respect_robots: bool = False, user_agent: str = UA):
        self.cache = Path(cache_dir) if cache_dir else None
        if self.cache:
            self.cache.mkdir(parents=True, exist_ok=True)
        self.min_interval, self.retries, self.block_after = min_interval, retries, block_after
        self.timeout, self.respect_robots, self.ua = timeout, respect_robots, user_agent
        self._last: dict[str, float] = {}
        self._refusals: dict[str, int] = {}
        self._locks: dict[str, threading.Lock] = {}
        self._glock = threading.Lock()
        self._robots: dict[str, urllib.robotparser.RobotFileParser | None] = {}
        self.stats = {"net": 0, "cache": 0, "errors": 0}

    # ---- кеш
    def _key(self, url: str, data: bytes | None) -> Path | None:
        if not self.cache:
            return None
        h = hashlib.sha256(url.encode() + (b"\0" + data if data else b"")).hexdigest()[:40]
        return self.cache / h

    def _lock(self, host: str) -> threading.Lock:
        with self._glock:
            return self._locks.setdefault(host, threading.Lock())

    def blocked_hosts(self) -> list[str]:
        return sorted(h for h, n in self._refusals.items() if n >= self.block_after)

    def _allowed_by_robots(self, url: str) -> bool:
        if not self.respect_robots:
            return True
        u = urllib.parse.urlparse(url)
        base = f"{u.scheme}://{u.netloc}"
        if base not in self._robots:
            rp = urllib.robotparser.RobotFileParser(base + "/robots.txt")
            try:
                rp.read()
                self._robots[base] = rp
            except Exception:
                self._robots[base] = None
        rp = self._robots[base]
        return True if rp is None else rp.can_fetch(self.ua, url)

    def get(self, url: str, data: bytes | None = None, headers: dict | None = None, use_cache: bool = True) -> bytes:
        key = self._key(url, data)
        if use_cache and key and key.exists():
            self.stats["cache"] += 1
            return key.read_bytes()
        host = urllib.parse.urlparse(url).netloc
        if self._refusals.get(host, 0) >= self.block_after:
            raise HostBlocked(f"{host}: запити припинено після {self.block_after} відмов поспіль")
        if not self._allowed_by_robots(url):
            raise HostBlocked(f"{host}: robots.txt забороняє {url}")
        last_err: Exception | None = None
        for attempt in range(self.retries):
            with self._lock(host):  # серіалізуємо запити до одного хоста + пауза
                wait = self.min_interval - (time.monotonic() - self._last.get(host, 0))
                if wait > 0:
                    time.sleep(wait)
                req = urllib.request.Request(url, data=data, headers={"User-Agent": self.ua, **(headers or {})})
                try:
                    with urllib.request.urlopen(req, timeout=self.timeout) as r:
                        body = r.read()
                    self._last[host] = time.monotonic()
                    self._refusals[host] = 0
                    self.stats["net"] += 1
                    if key:
                        key.write_bytes(body)
                    return body
                except urllib.error.HTTPError as e:
                    self._last[host] = time.monotonic()
                    last_err = e
                    if e.code in (401, 403, 429):
                        self._refusals[host] = self._refusals.get(host, 0) + 1
                        if self._refusals[host] >= self.block_after:
                            self.stats["errors"] += 1
                            raise HostBlocked(f"{host}: HTTP {e.code} ×{self._refusals[host]} — зупиняюсь, фіксую блокування") from e
                    if e.code in (404, 410):
                        self.stats["errors"] += 1
                        raise
                    retry_after = e.headers.get("Retry-After") if e.headers else None
                    pause = int(retry_after) if retry_after and retry_after.isdigit() else 2 ** (attempt + 1)
                except Exception as e:  # мережеві збої/таймаут
                    last_err = e
                    pause = 2 ** (attempt + 1)
            time.sleep(min(pause, 60))
        self.stats["errors"] += 1
        assert last_err is not None
        raise last_err

    def get_json(self, url: str, data: dict | None = None, **kw):
        body = json.dumps(data).encode() if data is not None else None
        hdr = {"Content-Type": "application/json", "Accept": "application/json"} if data is not None else {}
        return json.loads(self.get(url, data=body, headers=hdr, **kw))

    def map(self, fn, items, workers: int = 4):
        """Паралельно по різних хостах; до одного хоста запити однаково йдуть по черзі (див. _lock)."""
        out = {}
        with ThreadPoolExecutor(max_workers=workers) as ex:
            futs = {ex.submit(fn, it): it for it in items}
            for fut, it in futs.items():
                try:
                    out[it] = fut.result()
                except Exception as e:
                    out[it] = e
        return out
