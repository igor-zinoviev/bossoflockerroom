"""Модель родоводу та перевірки несуперечності (цикли, вік батьків, тезки, сила доказів).

Читає реєстри у форматі навички ex-ussr-kinship-research: person-register.csv, relationship-register.csv.
Усі перевірки повертають пояснювані повідомлення (severity: ERROR / WARN / INFO), нічого не «виправляють» мовчки.
"""
from __future__ import annotations

import csv
import re
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

PARENT_TYPES = {"parent-of"}
SPOUSE_TYPES = {"spouse-of"}
STRONG = {"corroborated", "strongly-corroborated"}


@dataclass
class Issue:
    severity: str
    code: str
    message: str
    ids: tuple = ()

    def __str__(self) -> str:
        return f"[{self.severity}] {self.code}: {self.message}" + (f" ({', '.join(self.ids)})" if self.ids else "")


@dataclass
class Person:
    pid: str
    label: str = ""
    birth: int | None = None
    death: int | None = None
    living: str = "unknown"
    sex: str = ""
    raw: dict = field(default_factory=dict)


def year_of(text: str | None) -> int | None:
    m = re.search(r"(1[5-9]\d\d|20\d\d)", text or "")
    return int(m.group(1)) if m else None


def load_registers(case_dir: str | Path):
    case = Path(case_dir)
    with (case / "person-register.csv").open(encoding="utf-8", newline="") as fh:
        persons = {r["person_id"]: Person(r["person_id"], r.get("preferred_label", ""), year_of(r.get("birth_estimate")),
                                          year_of(r.get("death_estimate")), r.get("living_status", "unknown"), raw=r)
                   for r in csv.DictReader(fh)}
    with (case / "relationship-register.csv").open(encoding="utf-8", newline="") as fh:
        rels = list(csv.DictReader(fh))
    return persons, rels


def parents_map(rels):
    """child -> [(parent, rel_row)]"""
    m = defaultdict(list)
    for r in rels:
        if r["relationship_type"] in PARENT_TYPES:
            m[r["person_b_id"]].append((r["person_a_id"], r))
    return m


def find_cycles(rels) -> list[list[str]]:
    graph = defaultdict(list)
    for r in rels:
        if r["relationship_type"] in PARENT_TYPES:
            graph[r["person_a_id"]].append(r["person_b_id"])  # батько -> дитина
    cycles, state, stack = [], {}, []

    def dfs(u):
        state[u] = 1
        stack.append(u)
        for v in graph.get(u, []):
            if state.get(v) == 1:
                cycles.append(stack[stack.index(v):] + [v])
            elif state.get(v) is None:
                dfs(v)
        stack.pop()
        state[u] = 2

    for node in list(graph):
        if state.get(node) is None:
            dfs(node)
    return cycles


def validate(persons: dict[str, Person], rels, mother_range=(14, 50), father_range=(15, 70)) -> list[Issue]:
    issues: list[Issue] = []
    for cyc in find_cycles(rels):
        issues.append(Issue("ERROR", "CYCLE", "Цикл у зв'язках «батько→дитина»: " + " → ".join(cyc), tuple(cyc)))
    pm = parents_map(rels)
    for child, plist in pm.items():
        c = persons.get(child)
        if not c:
            issues.append(Issue("ERROR", "MISSING_PERSON", f"{child} є в зв'язках, але немає в реєстрі особи", (child,)))
            continue
        for par, row in plist:
            p = persons.get(par)
            if not p:
                issues.append(Issue("ERROR", "MISSING_PERSON", f"{par} є в зв'язках, але немає в реєстрі особи", (par,)))
                continue
            if p.birth and c.birth:
                age = c.birth - p.birth
                lo, hi = (father_range if p.sex == "M" else mother_range if p.sex == "F" else (14, 70))
                if age < lo:
                    issues.append(Issue("ERROR", "PARENT_TOO_YOUNG", f"{par} мав би бути {age} р. на момент народження {child}", (par, child)))
                elif age > hi:
                    issues.append(Issue("WARN", "PARENT_TOO_OLD", f"{par} мав би бути {age} р. на момент народження {child}", (par, child)))
            if p.death and c.birth and c.birth > p.death + 1:
                issues.append(Issue("ERROR", "BORN_AFTER_PARENT_DEATH", f"{child} народжений ({c.birth}) після смерті {par} ({p.death})", (par, child)))
        # за нормою має бути не більше двох біологічних батьків
        if len({par for par, _ in plist}) > 2:
            issues.append(Issue("WARN", "MANY_PARENTS", f"У {child} більше двох батьків у реєстрі", (child,)))
    # тезки: однакове нормалізоване ім'я і той самий рік народження в одному дереві
    from .names import skeleton
    seen = defaultdict(list)
    for p in persons.values():
        key = (skeleton(p.label.split()[0]) if p.label else "", skeleton(p.label.split()[-1]) if p.label else "", p.birth)
        seen[key].append(p.pid)
    for key, ids in seen.items():
        if len(ids) > 1 and key[2]:
            issues.append(Issue("WARN", "HOMONYMS", f"Однакові ім'я/прізвище/рік {key[2]}: розведіть або злийте з обґрунтуванням", tuple(ids)))
    # сила доказів
    for r in rels:
        st = (r.get("status") or "").strip()
        groups = {g.strip().casefold() for g in re.split(r"[;,]", r.get("independence_groups", "")) if g.strip()}
        if st in STRONG and len(groups) < 2:
            issues.append(Issue("ERROR", "WEAK_EVIDENCE", f"Зв'язок {r['relationship_id']} має статус {st}, але лише {len(groups)} груп незалежності", (r["relationship_id"],)))
    return issues


def summarize(issues: list[Issue]) -> str:
    c = defaultdict(int)
    for i in issues:
        c[i.severity] += 1
    return ", ".join(f"{k}={v}" for k, v in sorted(c.items())) or "проблем не знайдено"
