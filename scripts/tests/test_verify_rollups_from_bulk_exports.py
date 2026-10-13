import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_rollups_from_bulk_exports import FIELDS, compare_rollups, number


def donation(status, reason=None, contact="C1"):
    return {"npe03__Contact__c": contact, "npe03__Open_Ended_Status__c": status,
            "Motivo_de_cierre_de_DDRR__c": reason}


def contact(*counts, record_id="C1"):
    return {"Id": record_id, **dict(zip(FIELDS, counts))}


class VerificationTests(unittest.TestCase):
    def test_business_categories_are_exclusive_with_real_and_legacy_values(self):
        donations = [donation("Open"), donation("Operational"), donation("Paused"),
                     donation("Closed", "Regla de negocios"), donation("Suspended", "Reactivación"),
                     donation("Closed", "Reactivacion"), donation("Closed"), donation("Failed")]
        result = compare_rollups(donations, [contact(8, 2, 4, 1, 1, 1, 2)])
        self.assertEqual([], result["mismatches"])
        self.assertEqual([], result["missing_contacts"])

    def test_null_is_not_zero_even_when_zero_is_expected(self):
        result = compare_rollups([donation("Open")], [contact(1, 1, 0, None, 0, 0, 0)])
        self.assertEqual(1, len(result["mismatches"]))
        self.assertIsNone(result["mismatches"][0]["actual"][FIELDS[3]])

    def test_missing_contact_and_stale_counter_without_donations(self):
        result = compare_rollups([donation("Open")], [contact(1, 1, 0, 0, 0, 0, 0, record_id="C2")])
        self.assertEqual(["C1"], result["missing_contacts"])
        self.assertEqual(["C2"], result["extra_contacts"])
        self.assertEqual(1, len(result["mismatches"]))
        self.assertEqual(0, result["mismatches"][0]["expected"][FIELDS[0]])

    def test_initialized_zero_contact_without_donations_is_valid(self):
        result = compare_rollups([], [contact(0, 0, 0, 0, 0, 0, 0)])
        self.assertEqual([], result["mismatches"])

    def test_unlinked_donation_does_not_create_a_contact_bucket(self):
        result = compare_rollups([donation("Open", contact=None)], [])
        self.assertEqual(0, result["contacts_expected_from_donations"])

    def test_duplicate_sources_are_rejected(self):
        with self.assertRaises(ValueError):
            compare_rollups([], [contact(0, 0, 0, 0, 0, 0, 0)] * 2)
        row = {"Id": "D1", **donation("Open")}
        with self.assertRaises(ValueError):
            compare_rollups([row, row], [])

    def test_numbers_are_exact_and_invalid_counters_fail(self):
        self.assertEqual(999999999999999999, number("999999999999999999"))
        self.assertIsNone(number(None))
        for value in ("1.5", "NaN", "Infinity", "-1", True, "invalid"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                number(value)

    def test_missing_source_column_is_rejected(self):
        with self.assertRaises(ValueError):
            compare_rollups([{"npe03__Contact__c": "C1"}], [])


if __name__ == "__main__":
    unittest.main()
