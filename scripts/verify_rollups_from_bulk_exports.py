import argparse
import json
from collections import Counter, defaultdict
from decimal import Decimal, InvalidOperation
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DONATIONS_FILE = ROOT / "outputs" / "prod_recurring_donations_for_rollup_verification.json"
CONTACTS_FILE = ROOT / "outputs" / "prod_contacts_for_rollup_verification.json"

FIELDS = [
    "Total_Recurring_Donations__c",
    "Open_Recurring_Donations__c",
    "Closed_Recurring_Donations__c",
    "Paused_Recurring_Donations__c",
    "Closed_Active_Recurring_Donations__c",
    "Closed_Passive_Recurring_Donations__c",
    "Closed_Reactivation_RDs__c",
]


def number(value):
    if value in (None, ""):
        return None
    if isinstance(value, bool):
        raise ValueError("Boolean counter is not a number")
    try:
        parsed = Decimal(str(value))
    except InvalidOperation as error:
        raise ValueError("Invalid counter value") from error
    if not parsed.is_finite() or parsed < 0 or parsed != parsed.to_integral_value():
        raise ValueError("Counters must be finite nonnegative integers")
    return int(parsed)


def compare_rollups(donations, contacts):
    expected = defaultdict(lambda: {field: 0 for field in FIELDS})
    status_counts = Counter()
    seen_donations = set()
    for donation in donations:
        if donation.get("Id"):
            if donation["Id"] in seen_donations:
                raise ValueError("Duplicate donation Id in source export")
            seen_donations.add(donation["Id"])
        required = {"npe03__Contact__c", "npe03__Open_Ended_Status__c", "Motivo_de_cierre_de_DDRR__c"}
        if not required.issubset(donation):
            raise ValueError("Donation export is missing required columns")
        contact_id = donation["npe03__Contact__c"]
        if not contact_id:
            continue
        status = donation["npe03__Open_Ended_Status__c"]
        reason = donation["Motivo_de_cierre_de_DDRR__c"]
        status_counts[status if status is not None else "<blank>"] += 1
        row = expected[contact_id]
        row[FIELDS[0]] += 1
        if status in ("Open", "Operational"):
            row[FIELDS[1]] += 1
        elif status in ("Closed", "Suspended"):
            row[FIELDS[2]] += 1
            if reason == "Regla de negocios":
                row[FIELDS[5]] += 1
            elif reason in ("Reactivación", "Reactivacion"):
                row[FIELDS[6]] += 1
            else:
                row[FIELDS[4]] += 1
        elif status == "Paused":
            row[FIELDS[3]] += 1

    contacts_by_id = {}
    for contact in contacts:
        if not contact.get("Id"):
            raise ValueError("Contact export is missing an Id")
        if contact["Id"] in contacts_by_id:
            raise ValueError("Duplicate Contact Id in source export")
        contacts_by_id[contact["Id"]] = contact

    missing = sorted(set(expected) - set(contacts_by_id))
    extra = sorted(set(contacts_by_id) - set(expected))
    mismatches = []
    for contact_id, contact in contacts_by_id.items():
        expected_counts = expected.get(contact_id, {field: 0 for field in FIELDS})
        actual = {field: number(contact.get(field)) for field in FIELDS}
        if actual != expected_counts:
            mismatches.append({"Id": contact_id, "expected": expected_counts, "actual": actual})
    return {
        "donations_checked": len(donations),
        "contacts_expected_from_donations": len(expected),
        "contacts_exported": len(contacts_by_id),
        "missing_contacts": missing,
        "extra_contacts": extra,
        "mismatches": mismatches,
        "status_counts": dict(status_counts),
    }


def load_records(path):
    with path.open("r", encoding="utf-8-sig") as handle:
        data = json.load(handle, parse_float=Decimal)
    if isinstance(data, dict):
        data = data.get("result", data)
        if isinstance(data, dict):
            data = data.get("records")
    if not isinstance(data, list):
        raise ValueError("Expected a JSON record array")
    return data


def main():
    parser = argparse.ArgumentParser(description="Compare approved DR/Contact exports; reads local files only.")
    parser.add_argument("--donations", type=Path, default=DONATIONS_FILE)
    parser.add_argument("--contacts", type=Path, nargs="+", default=[CONTACTS_FILE])
    parser.add_argument("--details", action="store_true", help="Include the first ten record IDs and differences")
    args = parser.parse_args()
    try:
        contacts = [record for path in args.contacts for record in load_records(path)]
        result = compare_rollups(load_records(args.donations), contacts)
    except (OSError, ValueError, TypeError, KeyError) as error:
        parser.exit(2, f"Verification failed: {error}\n")
    for key in ("donations_checked", "contacts_expected_from_donations", "contacts_exported"):
        print(f"{key}={result[key]}")
    print(f"missing_contacts={len(result['missing_contacts'])}")
    print(f"extra_contacts={len(result['extra_contacts'])}")
    print(f"mismatched_contacts={len(result['mismatches'])}")
    print("status_counts=" + json.dumps(result["status_counts"], ensure_ascii=False, sort_keys=True))
    if args.details:
        for key in ("missing_contacts", "extra_contacts", "mismatches"):
            print(f"first_{key}=" + json.dumps(result[key][:10], ensure_ascii=False))
    return 1 if result["missing_contacts"] or result["mismatches"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
