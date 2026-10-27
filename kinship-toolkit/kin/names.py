"""Фонетичний «скелет» прізвищ і імен для зіставлення написань різних мов і епох.

Приклад: Borysów, Borysiv, Борисів, Borisow, Borysiw дають однаковий скелет «borisV».
Це евристика для відбору кандидатів, а не доказ тотожності: рішення про злиття приймає entity.py з урахуванням дат і місць.
"""
from __future__ import annotations

import re
import unicodedata

_CYR = {
    "а": "a", "б": "b", "в": "v", "г": "h", "ґ": "g", "д": "d", "е": "e", "є": "e", "ё": "o", "ж": "z", "з": "z",
    "и": "i", "і": "i", "ї": "i", "й": "j", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
    "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "c", "ч": "c", "ш": "s", "щ": "s", "ъ": "", "ы": "i",
    "ь": "", "э": "e", "ю": "u", "я": "a", "'": "", "’": "", "ʼ": "",
}
_POLISH = {"ł": "l", "ś": "s", "ć": "c", "ń": "n", "ź": "z", "ż": "z", "ą": "a", "ę": "e", "ó": "o"}
# закінчення -ів/-ов/-ев/-ów тощо зводимо до одного маркера V; -ський/-ski/-ska до SK
_END_V = re.compile(r"(iev|iew|jev|jew|yev|yew|ev|ew|ov|ow|iv|iw|yv|yw|of|off)$")
_END_SK = re.compile(r"(sk(i|y|yi|ij|yj|iy|a|oi|oj)?)$")


def _strip_marks(text: str) -> str:
    out = []
    for ch in unicodedata.normalize("NFC", text.lower()):
        out.append(_POLISH.get(ch, ch))
    s = unicodedata.normalize("NFKD", "".join(out))
    return "".join(c for c in s if not unicodedata.combining(c))


def skeleton(name: str) -> str:
    """Повертає нормалізований фонетичний скелет прізвища або імені."""
    s = _strip_marks(name)
    s = "".join(_CYR.get(c, c) for c in s)
    s = re.sub(r"[^a-z]", "", s)
    if not s:
        return ""
    # латинські диграфи
    for pat, rep in (("shch", "s"), ("sch", "s"), ("sz", "s"), ("sh", "s"), ("cz", "c"), ("ch", "h"), ("kh", "h"),
                     ("x", "h"), ("ts", "c"), ("dz", "z"), ("ck", "k"), ("ph", "f"), ("qu", "k")):
        s = s.replace(pat, rep)
    s = s.replace("w", "v").replace("y", "i").replace("j", "i").replace("z", "s").replace("g", "h")
    s = re.sub(r"(.)\1+", r"\1", s)  # подвоєння
    s = re.sub(r"i+", "i", s)
    m = _END_SK.search(s)
    if m and len(s) - len(m.group(0)) >= 3:
        return s[: m.start()] + "SK"
    m = _END_V.search(s)
    if m and len(s) - len(m.group(0)) >= 3:
        return s[: m.start()] + "V"
    return s


def levenshtein(a: str, b: str) -> int:
    if a == b:
        return 0
    if not a or not b:
        return max(len(a), len(b))
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def similarity(a: str, b: str) -> float:
    """0..1 за скелетами; 1.0 — однаковий скелет."""
    sa, sb = skeleton(a), skeleton(b)
    if not sa or not sb:
        return 0.0
    if sa == sb:
        return 1.0
    d = levenshtein(sa, sb)
    base = 1 - d / max(len(sa), len(sb))
    return max(0.0, round(base, 3))


# Спрощена таблиця пар імен: церковна/народна/польська/латинська форми (розширюйте під свою справу).
GIVEN_GROUPS = [
    {"ivan", "ioann", "jan", "joannes", "iwan", "ioan", "johann", "hryc", "ivanko"},
    {"dmitro", "dmitri", "dymitr", "dmytro", "demetrius", "dimitrii", "dmitrii"},
    {"mikola", "nikolai", "mikolai", "nicolaus", "mikołaj", "mykola"},
    {"mihail", "mihaio", "michael", "michal", "mihas", "mihasio", "mishko", "mihailo"},
    {"semen", "simeon", "siemion", "senko", "semko", "simon", "semion", "semeon"},
    {"marija", "maria", "marianna", "marja"},
    {"olexandra", "aleksandra", "alexandra", "oleksandra", "sasha"},
    {"hrihorii", "grigorii", "grzegorz", "gregorius", "hryhorij", "grigori", "hryhorii"},
    {"viktor", "wiktor", "victor"},
    {"rosalia", "rozalia", "rozalija", "rosalie"},
    {"nadia", "nadija", "nadezda", "nadiia", "nadzieja"},
]


def given_name_match(a: str, b: str) -> float:
    """1.0 — те саме ім'я або в одній групі форм; інакше схожість скелетів (<=0.8)."""
    sa, sb = skeleton(a), skeleton(b)
    if not sa or not sb:
        return 0.0
    if sa == sb:
        return 1.0
    for grp in GIVEN_GROUPS:
        sk = {skeleton(x) for x in grp}
        if sa in sk and sb in sk:
            return 0.95
    return min(0.8, similarity(a, b))


_ALT = {"c": ["c", "cz", "ts"], "h": ["h", "ch", "kh"], "i": ["i", "y"], "k": ["k", "ck"], "o": ["o", "ó"],
        "s": ["s", "ś", "sz", "sh"], "u": ["u", "ú"], "v": ["v", "w"], "z": ["z", "ż", "zh"]}
_ALT_END = {"V": ["ów", "ow", "iv", "iw", "yv", "ev", "ew"], "SK": ["ski", "sky", "skyj", "skyi", "ska", "ськ"]}


def query_variants(surname: str, limit: int = 120) -> list[str]:
    """Правдоподібні написання прізвища для пошуку в індексах, що шукають лише точний збіг.

    Із «скелета» прізвища підставляються типові альтернативи (i/y, h/ch/kh, s/ś/sz, -ów/-ow/-iv/...).
    Приклад: «Михаськів» → ... «Mychaszkow», «Michaśków», «Mykhaskiv» (див. tests). Результат — кандидати для запитів, не доказ.
    """
    sk = skeleton(surname)
    end = ""
    for tail in _ALT_END:
        if sk.endswith(tail):
            sk, end = sk[: -len(tail)], tail
            break
    combos = [""]
    for ch in sk:
        opts = _ALT.get(ch, [ch])
        combos = [c + o for c in combos for o in opts]
        if len(combos) > limit * 20:
            combos = combos[: limit * 20]
    tails = _ALT_END.get(end, [""])
    out = []
    for c in combos:
        for t in tails:
            out.append((c + t).capitalize())
    seen, uniq = set(), []
    for v in out:  # найпоширеніші спочатку: сортуємо за кількістю «екзотичних» символів
        if v not in seen:
            seen.add(v)
            uniq.append(v)
    uniq.sort(key=lambda v: sum(ch in "śóúżćńł" for ch in v) + (len(v) - len(surname)) * 0.01)
    return uniq[:limit] if limit < 10 else uniq[: max(limit, 10)]
