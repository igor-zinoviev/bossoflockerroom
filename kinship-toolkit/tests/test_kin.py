"""Тести на синтетичних даних (жодних персональних даних)."""
import csv
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from kin import entity, gedcom, graph, names  # noqa: E402
from kin.fetch import Fetcher, HostBlocked  # noqa: E402


def mk_case(persons, rels):
    d = Path(tempfile.mkdtemp())
    with (d / "person-register.csv").open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["person_id", "preferred_label", "living_status", "birth_estimate", "death_estimate", "places", "candidate_status", "source_artifact_ids"])
        w.writeheader()
        for p in persons:
            w.writerow({k: p.get(k, "") for k in w.fieldnames})
    with (d / "relationship-register.csv").open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["relationship_id", "person_a_id", "relationship_type", "person_b_id", "status", "independence_groups"])
        w.writeheader()
        for r in rels:
            w.writerow({k: r.get(k, "") for k in w.fieldnames})
    return d


class Names(unittest.TestCase):
    def test_surname_variants_collapse(self):
        base = names.skeleton("Борисів")
        for v in ("Borysiv", "Borysów", "Borisow"):
            self.assertEqual(names.skeleton(v), base, v)
        self.assertEqual(names.skeleton("Ковальський"), names.skeleton("Kowalski"))

    def test_query_variants_cover_index_spellings(self):
        v = names.query_variants("Борисів", limit=400)
        for want in ("Borysów", "Boryszow", "Borisiv", "Borysiw"):
            self.assertIn(want, v)
        self.assertTrue(all(names.skeleton(x) == names.skeleton("Борисів") for x in v))

    def test_different_surnames_stay_apart(self):
        self.assertLess(names.similarity("Борисів", "Мельник"), 0.6)

    def test_given_names_across_languages(self):
        self.assertGreater(names.given_name_match("Іван", "Jan"), 0.9)
        self.assertLess(names.given_name_match("Іван", "Марія"), 0.5)


class Entity(unittest.TestCase):
    def test_age_constraint_blocks_merge(self):
        child = entity.Mention("m1", "Kowalski", "Jan", birth_year=1887, event_year=1887, place="Zalesie")
        owner = entity.Mention("m2", "Kowalski", "Jan", event_year=1899, min_age_at_event=21, place="Zalesie")
        self.assertTrue(entity.hard_conflicts(child, owner))
        clusters, joined, rejected = entity.cluster([child, owner])
        self.assertEqual(len(clusters), 2)
        self.assertTrue(rejected)

    def test_true_match_joins(self):
        a = entity.Mention("a", "Борисів", "Іван", birth_year=1935, place="Заліська", father_given="Микола")
        b = entity.Mention("b", "Borysów", "Jan", birth_year=1935, place="Заліська", father_given="Mikołaj")
        clusters, joined, _ = entity.cluster([a, b], threshold=0.7)
        self.assertEqual(len(clusters), 1)

    def test_parent_name_conflict(self):
        a = entity.Mention("a", "Nowak", "Jan", father_given="Piotr")
        b = entity.Mention("b", "Nowak", "Jan", father_given="Wojciech")
        self.assertTrue(entity.hard_conflicts(a, b))


class Graph(unittest.TestCase):
    def test_cycle_detected(self):
        d = mk_case([{"person_id": f"P-{i}", "preferred_label": f"X{i}"} for i in (1, 2, 3)],
                    [{"relationship_id": "R-1", "person_a_id": "P-1", "relationship_type": "parent-of", "person_b_id": "P-2"},
                     {"relationship_id": "R-2", "person_a_id": "P-2", "relationship_type": "parent-of", "person_b_id": "P-3"},
                     {"relationship_id": "R-3", "person_a_id": "P-3", "relationship_type": "parent-of", "person_b_id": "P-1"}])
        persons, rels = graph.load_registers(d)
        self.assertTrue(graph.find_cycles(rels))
        self.assertTrue(any(i.code == "CYCLE" for i in graph.validate(persons, rels)))

    def test_parent_age_and_weak_evidence(self):
        d = mk_case([{"person_id": "P-1", "preferred_label": "Батько", "birth_estimate": "1900"},
                     {"person_id": "P-2", "preferred_label": "Син", "birth_estimate": "1905"}],
                    [{"relationship_id": "R-1", "person_a_id": "P-1", "relationship_type": "parent-of", "person_b_id": "P-2",
                      "status": "corroborated", "independence_groups": "IG-A"}])
        persons, rels = graph.load_registers(d)
        codes = {i.code for i in graph.validate(persons, rels)}
        self.assertIn("PARENT_TOO_YOUNG", codes)
        self.assertIn("WEAK_EVIDENCE", codes)

    def test_clean_tree_has_no_errors(self):
        d = mk_case([{"person_id": "P-1", "preferred_label": "Іван Петренко", "birth_estimate": "1900"},
                     {"person_id": "P-2", "preferred_label": "Петро Петренко", "birth_estimate": "1930"}],
                    [{"relationship_id": "R-1", "person_a_id": "P-1", "relationship_type": "parent-of", "person_b_id": "P-2", "status": "hypothesis"}])
        persons, rels = graph.load_registers(d)
        self.assertFalse([i for i in graph.validate(persons, rels) if i.severity == "ERROR"])


class Gedcom(unittest.TestCase):
    def setUp(self):
        self.d = mk_case(
            [{"person_id": "P-1", "preferred_label": "Іван Петренко", "birth_estimate": "1900-03-04", "places": "Львів"},
             {"person_id": "P-2", "preferred_label": "Марія Петренко", "birth_estimate": "~1905"},
             {"person_id": "P-3", "preferred_label": "Петро Петренко", "birth_estimate": "1930"},
             {"person_id": "P-4", "preferred_label": "Жива Особа", "living_status": "living", "birth_estimate": "1990-01-01"}],
            [{"relationship_id": "R-1", "person_a_id": "P-1", "relationship_type": "spouse-of", "person_b_id": "P-2", "status": "hypothesis"},
             {"relationship_id": "R-2", "person_a_id": "P-1", "relationship_type": "parent-of", "person_b_id": "P-3", "status": "hypothesis"},
             {"relationship_id": "R-3", "person_a_id": "P-2", "relationship_type": "parent-of", "person_b_id": "P-3", "status": "hypothesis"},
             {"relationship_id": "R-4", "person_a_id": "P-3", "relationship_type": "parent-of", "person_b_id": "P-4", "status": "hypothesis"}])

    def test_export_validates_and_redacts(self):
        persons, rels = graph.load_registers(self.d)
        text = gedcom.export(persons, rels)
        self.assertEqual(gedcom.validate_gedcom(text), [])
        self.assertIn("Private /Private/", text)
        self.assertNotIn("1990", text)
        self.assertIn("2 DATE 4 MAR 1900", text)
        self.assertIn("ABT 1905", text)

    def test_single_parent_joins_existing_couple(self):
        persons, rels = graph.load_registers(self.d)
        text = gedcom.export(persons, rels)
        self.assertEqual(text.count(" FAM\n"), 2)  # пара {1,2} з дитиною 3 і сім'я {3} з дитиною 4

    def test_validator_catches_broken_pointer(self):
        bad = "0 HEAD\n0 @I1@ INDI\n1 FAMC @F9@\n0 TRLR\n"
        self.assertTrue(gedcom.validate_gedcom(bad))

    def test_long_note_is_wrapped(self):
        text = "\n".join(gedcom._wrap(1, "NOTE", "а" * 700))
        self.assertTrue(all(len(l) <= 255 for l in text.splitlines()))


class FetcherBehaviour(unittest.TestCase):
    def test_host_blocked_after_refusals(self):
        f = Fetcher(min_interval=0, block_after=2, retries=1)
        f._refusals["example.invalid"] = 2
        with self.assertRaises(HostBlocked):
            f.get("https://example.invalid/x")
        self.assertEqual(f.blocked_hosts(), ["example.invalid"])

    def test_cache_hit_no_network(self):
        d = tempfile.mkdtemp()
        f = Fetcher(cache_dir=d, min_interval=0)
        key = f._key("https://example.invalid/a", None)
        key.write_bytes(b"cached")
        self.assertEqual(f.get("https://example.invalid/a"), b"cached")
        self.assertEqual(f.stats["cache"], 1)


if __name__ == "__main__":
    unittest.main()
