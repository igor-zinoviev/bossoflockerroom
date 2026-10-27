"""Експорт реєстрів у GEDCOM 5.5.1 та незалежна перевірка результату.

- Живі особи за замовчуванням приховуються (ім'я «Private», без дат, RESN privacy).
- Усі зв'язки позначаються статусом доказовості в NOTE; нічого не видається за доведене.
- validate_gedcom() перевіряє структуру, посилання, симетрію FAMC/FAMS, довжину рядків і відсутність
  «предка самого себе»; при бажанні додатково прогоняється через python-gedcom (pip install python-gedcom).
"""
from __future__ import annotations

import re
from collections import defaultdict

from .graph import Person, year_of

MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
FEMALE_WORDS = ("дружина", "мати", "бабуся", "wife")
MALE_NAMES_A = {"микола", "лука", "хома", "кузьма", "сава", "ілля", "данила", "микита", "лев"}


def guess_sex(label: str) -> str:
    """Евристика за українськими закінченнями; порожній рядок — якщо неясно."""
    low = label.casefold()
    toks = re.findall(r"[\w'’ʼ-]+", low)
    if any(t.endswith(("івна", "ївна", "овна", "ична")) for t in toks):
        return "F"
    if any(t.endswith(("ович", "йович", "евич", "ійович")) for t in toks):
        return "M"
    if any(w in low for w in FEMALE_WORDS):
        return "F"
    if any(w in low for w in ("батько", "дід")):
        return "M"
    for t in toks:
        if t.endswith(("ська", "цька", "зька", "ова", "єва", "іна")) and t not in MALE_NAMES_A:
            return "F"
        if t.endswith("ńska") or t.endswith("ska"):
            return "F"
    for t in toks:
        if t.endswith(("а", "я")) and t not in MALE_NAMES_A and len(t) > 3:
            return "F"
    return "M" if toks else ""


def fmt_date(text: str | None) -> str:
    if not text:
        return ""
    t = text.strip()
    approx = bool(re.search(r"(~|±|ок\.|близько|прибл|abt|XVII|ст\.|чи щось)", t, re.I))
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", t)
    if m and not approx:
        return f"{int(m.group(3))} {MONTHS[int(m.group(2)) - 1]} {m.group(1)}"
    if m:
        return f"ABT {m.group(1)}"
    y = year_of(t)
    if y:
        return f"ABT {y}" if approx else str(y)
    return ""


def _wrap(level: int, tag: str, value: str) -> list[str]:
    """Розбиває довге значення за CONC (ліміт 255 символів на рядок)."""
    first = f"{level} {tag} "
    room = 240 - len(first)
    value = value.replace("\n", " ").replace("@", "@@")
    lines, chunk, rest = [], value[:room], value[room:]
    lines.append((first + chunk).rstrip())
    while rest:
        lines.append(f"{level + 1} CONC {rest[:230]}")
        rest = rest[230:]
    return lines


def split_name(label: str) -> tuple[str, str]:
    """«Борисів Іван Миколайович» → (Іван Миколайович, Борисів); без хиби на дужки."""
    core = re.sub(r"\(.*?\)", "", label).strip().split(",")[0]
    toks = core.split()
    if len(toks) >= 2 and re.search(r"(ськ|цьк|ов|ев|єв|ін|ів|ński|ska|ski)", toks[0].casefold()) and not toks[0].endswith(("ович",)):
        return " ".join(toks[1:]), toks[0]
    if len(toks) >= 2:
        return " ".join(toks[:-1]), toks[-1]
    return core, ""


def export(persons: dict[str, Person], rels: list[dict], redact_living: bool = True, sex_overrides: dict | None = None,
           title: str = "Родовід (ГІПОТЕЗА)", header_note: str = "") -> str:
    ix = {pid: i + 1 for i, pid in enumerate(sorted(persons))}
    sex = {}
    inferred = set()
    for pid, p in persons.items():
        s = (sex_overrides or {}).get(pid) or p.sex
        if not s:
            s = guess_sex(p.label)
            if s:
                inferred.add(pid)
        sex[pid] = s
    fams: dict[frozenset, dict] = {}
    for r in rels:
        t = r["relationship_type"]
        if t == "spouse-of":
            fams.setdefault(frozenset({r["person_a_id"], r["person_b_id"]}), {"children": [], "rels": []})["rels"].append(r)
    child_parents = defaultdict(list)
    for r in rels:
        if r["relationship_type"] == "parent-of":
            child_parents[r["person_b_id"]].append((r["person_a_id"], r))
    for child, plist in child_parents.items():
        key = frozenset(pid for pid, _ in plist)
        # відомий лише один із батьків, але є подружня пара, що його охоплює, — дитина йде в ту саму сім'ю
        supers = [k for k in fams if key < k]
        if key not in fams and len(supers) == 1:
            key = supers[0]
        fam = fams.setdefault(key, {"children": [], "rels": []})
        fam["children"].append(child)
        fam["rels"] += [r for _, r in plist]
    fam_id = {k: i + 1 for i, k in enumerate(sorted(fams, key=lambda k: sorted(k)))}
    famc, fams_of = defaultdict(list), defaultdict(list)
    for k, v in fams.items():
        for c in v["children"]:
            famc[c].append(fam_id[k])
        for pid in k:
            fams_of[pid].append(fam_id[k])

    out = ["0 HEAD", "1 SOUR ex-ussr-kinship-research", "2 NAME kinship-toolkit", "1 GEDC", "2 VERS 5.5.1", "2 FORM LINEAGE-LINKED",
           "1 CHAR UTF-8", *_wrap(1, "NOTE", header_note or "УВАГА: усі зв'язки — гіпотези за статусами в реєстрах; не імпортувати в публічні дерева як доведені. " + title)]
    for pid in sorted(persons):
        p = persons[pid]
        out.append(f"0 @I{ix[pid]}@ INDI")
        living = redact_living and p.living == "living"
        if living:
            out += ["1 NAME Private /Private/", *( [f"1 SEX {sex[pid]}"] if sex[pid] else [] ), "1 RESN privacy"]
        else:
            given, sur = split_name(p.label)
            out.append(f"1 NAME {given} /{sur}/".replace("@", "@@"))
            if sex[pid]:
                out.append(f"1 SEX {sex[pid]}")
            b, d = fmt_date(p.raw.get("birth_estimate")), fmt_date(p.raw.get("death_estimate"))
            pl = (p.raw.get("places") or "").split(";")[0].strip()
            if b or pl:
                out.append("1 BIRT")
                if b:
                    out.append(f"2 DATE {b}")
                if pl:
                    out += _wrap(2, "PLAC", pl)
            if d:
                out += ["1 DEAT", f"2 DATE {d}"]
            note = f"Реєстр {pid}; статус кандидата: {p.raw.get('candidate_status', '')}; артефакти: {p.raw.get('source_artifact_ids', '')}."
            if pid in inferred:
                note += " Стать виведена евристично з імені."
            out += _wrap(1, "NOTE", note)
        for f in famc[pid]:
            out.append(f"1 FAMC @F{f}@")
        for f in fams_of[pid]:
            out.append(f"1 FAMS @F{f}@")
    for k in sorted(fams, key=lambda k: fam_id[k]):
        v = fams[k]
        out.append(f"0 @F{fam_id[k]}@ FAM")
        members = sorted(k)
        husb = next((m for m in members if sex[m] == "M"), None)
        wife = next((m for m in members if sex[m] == "F" and m != husb), None)
        rest = [m for m in members if m not in (husb, wife)]
        if husb is None and rest:
            husb = rest.pop(0)
        if wife is None and rest:
            wife = rest.pop(0)
        if husb:
            out.append(f"1 HUSB @I{ix[husb]}@")
        if wife:
            out.append(f"1 WIFE @I{ix[wife]}@")
        for c in sorted(set(v["children"])):
            out.append(f"1 CHIL @I{ix[c]}@")
        ids = sorted({r["relationship_id"] for r in v["rels"]})
        sts = sorted({r.get("status", "") for r in v["rels"]})
        out += _wrap(1, "NOTE", f"Реєстр зв'язків {', '.join(ids)}; статуси: {', '.join(sts)}.")
    out.append("0 TRLR")
    return "\n".join(out) + "\n"


def validate_gedcom(text: str) -> list[str]:
    """Повертає список проблем (порожній = структура коректна)."""
    errs: list[str] = []
    lines = text.splitlines()
    if not lines or lines[0] != "0 HEAD":
        errs.append("файл має починатися з «0 HEAD»")
    if not lines or lines[-1] != "0 TRLR":
        errs.append("файл має закінчуватися «0 TRLR»")
    defined, pointers = {}, []
    prev = 0
    cur = None
    indi, fam = {}, {}
    for n, ln in enumerate(lines, 1):
        if len(ln) > 255:
            errs.append(f"рядок {n}: довший за 255 символів")
        m = re.match(r"^(\d+) (?:(@[^@\s]+@) )?(\S+)(?: (.*))?$", ln)
        if not m:
            errs.append(f"рядок {n}: неправильний формат «{ln[:40]}»")
            continue
        lvl, xref, tag, val = int(m.group(1)), m.group(2), m.group(3), m.group(4) or ""
        if lvl > prev + 1:
            errs.append(f"рядок {n}: стрибок рівня {prev}→{lvl}")
        prev = lvl
        if lvl == 0:
            cur = None
            if xref:
                if xref in defined:
                    errs.append(f"рядок {n}: повторне означення {xref}")
                defined[xref] = tag
                cur = (xref, tag)
                if tag == "INDI":
                    indi[xref] = {"FAMC": [], "FAMS": []}
                elif tag == "FAM":
                    fam[xref] = {"HUSB": [], "WIFE": [], "CHIL": []}
        elif lvl == 1 and cur:
            if re.fullmatch(r"@[^@\s]+@", val.strip()):
                pointers.append((n, val.strip()))
                if cur[1] == "INDI" and tag in ("FAMC", "FAMS"):
                    indi[cur[0]][tag].append(val.strip())
                if cur[1] == "FAM" and tag in ("HUSB", "WIFE", "CHIL"):
                    fam[cur[0]][tag].append(val.strip())
    for n, ptr in pointers:
        if ptr not in defined:
            errs.append(f"рядок {n}: посилання на невизначений {ptr}")
    for f, v in fam.items():
        for tag, back in (("HUSB", "FAMS"), ("WIFE", "FAMS"), ("CHIL", "FAMC")):
            for i in v[tag]:
                if i in indi and f not in indi[i][back]:
                    errs.append(f"{f}: {tag} {i}, але в {i} немає {back} {f}")
    for i, v in indi.items():
        for f in v["FAMC"]:
            if f in fam and i not in fam[f]["CHIL"]:
                errs.append(f"{i}: FAMC {f}, але {i} не в CHIL")
        for f in v["FAMS"]:
            if f in fam and i not in fam[f]["HUSB"] + fam[f]["WIFE"]:
                errs.append(f"{i}: FAMS {f}, але {i} не подружжя в {f}")
    # предок самого себе: ребро батько→дитина через сім'ї
    kids = defaultdict(set)
    for f, v in fam.items():
        for p in v["HUSB"] + v["WIFE"]:
            kids[p].update(v["CHIL"])
    state = {}

    def dfs(u, path):
        state[u] = 1
        for w in kids.get(u, ()):
            if state.get(w) == 1:
                errs.append("цикл походження: " + " → ".join(path + [u, w]))
            elif w not in state:
                dfs(w, path + [u])
        state[u] = 2

    for u in list(kids):
        if u not in state:
            dfs(u, [])
    return errs


def validate_with_python_gedcom(path: str) -> str:
    """Додаткова перевірка парсером python-gedcom, якщо він встановлений."""
    try:
        from gedcom.parser import Parser
    except ImportError:
        return "python-gedcom не встановлено (pip install python-gedcom) — пропущено"
    p = Parser()
    p.parse_file(path, strict=False)
    n = len([e for e in p.get_element_list() if e.get_tag() == "INDI"])
    return f"python-gedcom розібрав файл: {n} осіб"
