"""Крос-парафіяльне зіставлення згадок про людей (entity resolution) із поясненням.

Не заявляє «математичної оптимальності»: це прозора зважена оцінка + жорсткі обмеження, придатна для перевірки людиною.
Кожне рішення повертає список причин. Автоматичного злиття немає — лише кластери-кандидати.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

from .names import given_name_match, similarity

W = {"surname": 0.40, "given": 0.20, "year": 0.20, "place": 0.10, "parents": 0.10}


@dataclass
class Mention:
    mid: str
    surname: str
    given: str = ""
    birth_year: int | None = None          # якщо відомий
    event_year: int | None = None          # рік документа
    min_age_at_event: int | None = None    # напр. 18 для опікуна/власника
    born_by: int | None = None             # найпізніший можливий рік народження (мати дитини 1887 р. → ≤1873)
    place: str = ""
    father_given: str = ""
    mother_given: str = ""
    source: str = ""
    coords: tuple[float, float] | None = None
    extra: dict = field(default_factory=dict)


def haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371.0088 * math.asin(math.sqrt(h))


def hard_conflicts(a: Mention, b: Mention) -> list[str]:
    """Причини, чому дві згадки НЕ можуть бути однією особою."""
    out = []
    for x, y in ((a, b), (b, a)):
        if x.birth_year and y.event_year and y.min_age_at_event:
            if y.event_year - x.birth_year < y.min_age_at_event:
                out.append(f"{x.mid} (нар. {x.birth_year}) мав {y.event_year - x.birth_year} р. у {y.event_year}, а {y.mid} вимагає ≥{y.min_age_at_event}")
    for x, y in ((a, b), (b, a)):
        if x.birth_year and y.born_by and x.birth_year > y.born_by:
            out.append(f"{x.mid} нар. {x.birth_year}, а {y.mid} мав(ла) народитися не пізніше {y.born_by}")
    if a.birth_year and b.birth_year and abs(a.birth_year - b.birth_year) > 3:
        out.append(f"роки народження розходяться: {a.birth_year} vs {b.birth_year}")
    if a.father_given and b.father_given and given_name_match(a.father_given, b.father_given) < 0.5:
        out.append(f"різні імена батьків: {a.father_given} vs {b.father_given}")
    return out


def score(a: Mention, b: Mention, alias_places: dict[str, str] | None = None) -> tuple[float, list[str]]:
    why: list[str] = []
    s_sur = similarity(a.surname, b.surname)
    s_giv = given_name_match(a.given, b.given) if a.given and b.given else 0.5
    if a.birth_year and b.birth_year:
        s_year = math.exp(-abs(a.birth_year - b.birth_year) / 2.0)
    else:
        s_year = 0.5
    pa = (alias_places or {}).get(a.place.casefold(), a.place.casefold())
    pb = (alias_places or {}).get(b.place.casefold(), b.place.casefold())
    if pa and pb and pa == pb:
        s_pl = 1.0
    elif a.coords and b.coords:
        d = haversine_km(a.coords, b.coords)
        s_pl = 0.7 if d <= 10 else 0.3 if d <= 30 else 0.0
        why.append(f"відстань між місцями {d:.1f} км")
    else:
        s_pl = 0.3 if (not pa or not pb) else 0.0
    s_par = given_name_match(a.father_given, b.father_given) if a.father_given and b.father_given else 0.5
    total = W["surname"] * s_sur + W["given"] * s_giv + W["year"] * s_year + W["place"] * s_pl + W["parents"] * s_par
    why.append(f"прізвище {s_sur:.2f}, ім'я {s_giv:.2f}, рік {s_year:.2f}, місце {s_pl:.2f}, батьки {s_par:.2f}")
    return round(total, 3), why


def cluster(mentions: list[Mention], threshold: float = 0.75, alias_places: dict[str, str] | None = None):
    """Single-link кластери з жорсткими забороненими парами. Повертає (clusters, rejected_pairs)."""
    parent = {m.mid: m.mid for m in mentions}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    by_id = {m.mid: m for m in mentions}
    rejected, joined = [], []
    pairs = []
    for i, a in enumerate(mentions):
        for b in mentions[i + 1:]:
            conf = hard_conflicts(a, b)
            sc, why = score(a, b, alias_places)
            if conf:
                if sc >= threshold - 0.1:
                    rejected.append((a.mid, b.mid, sc, conf))
                continue
            if sc >= threshold:
                pairs.append((sc, a.mid, b.mid, why))
    for sc, x, y, why in sorted(pairs, reverse=True):
        rx, ry = find(x), find(y)
        if rx == ry:
            continue
        # перевірка, що злиття кластерів не створює заборонену пару
        mx = [m for m in mentions if find(m.mid) == rx]
        my = [m for m in mentions if find(m.mid) == ry]
        if any(hard_conflicts(p, q) for p in mx for q in my):
            rejected.append((x, y, sc, ["кластери містять несумісні згадки"]))
            continue
        parent[rx] = ry
        joined.append((x, y, sc, why))
    groups: dict[str, list[str]] = {}
    for m in mentions:
        groups.setdefault(find(m.mid), []).append(m.mid)
    return list(groups.values()), joined, rejected
