# Salesforce recurring donation rollups

Bulk-aware Contact counters, recurring donation status classification, merge handling, asynchronous backfill and verification.

**Stack:** Apex, Salesforce DX, NPSP, Python.

## What this demonstrates

Reusable implementation patterns for data integration, validation and maintainable automation. This is a curated, generalized portfolio edition. It contains no production exports, deployment history, internal access inventory or credentials. API names and source labels have been generalized where needed; configure the matching schema in your own sandbox before use.

## Getting started

For Salesforce work, use Salesforce CLI and a dedicated sandbox with the required schema and NPSP dependencies. Inspect `manifest/package.xml`, then validate with `sf project deploy start --dry-run --manifest manifest/package.xml --target-org DEMO_SANDBOX`. This repository has not been deployed or tested against a live org during portfolio preparation. 

## Source map

- `README.md`
- `force-app/main/default/classes/RecurringDonationContactRollupBatch.cls`
- `force-app/main/default/classes/RecurringDonationContactRollupBatch.cls-meta.xml`
- `force-app/main/default/classes/RecurringDonationContactRollupHandler.cls`
- `force-app/main/default/classes/RecurringDonationContactRollupHandler.cls-meta.xml`
- `force-app/main/default/classes/RecurringDonationContactRollupMerge.cls`
- `force-app/main/default/classes/RecurringDonationContactRollupMerge.cls-meta.xml`
- `force-app/main/default/classes/RecurringDonationContactRollupMergeJob.cls`
- `force-app/main/default/classes/RecurringDonationContactRollupMergeJob.cls-meta.xml`
- `force-app/main/default/classes/RecurringDonationContactRollupTest.cls`
- `force-app/main/default/classes/RecurringDonationContactRollupTest.cls-meta.xml`
- `force-app/main/default/objectTranslations/Contact-en_US.objectTranslation-meta.xml`
- `force-app/main/default/objects/Contact/fields/Closed_Active_Recurring_Donations__c.field-meta.xml`
- `force-app/main/default/objects/Contact/fields/Closed_Passive_Recurring_Donations__c.field-meta.xml`
- `force-app/main/default/objects/Contact/fields/Closed_Reactivation_RDs__c.field-meta.xml`
- `force-app/main/default/objects/Contact/fields/Closed_Recurring_Donations__c.field-meta.xml`
- `force-app/main/default/objects/Contact/fields/Open_Recurring_Donations__c.field-meta.xml`
- `force-app/main/default/objects/Contact/fields/Paused_Recurring_Donations__c.field-meta.xml`
- `force-app/main/default/objects/Contact/fields/Total_Recurring_Donations__c.field-meta.xml`
- `force-app/main/default/permissionsets/Recurring_Donation_Contact_Rollup_Access.permissionset-meta.xml`
- `manifest/package.xml`
- `scripts/__pycache__/verify_rollups_from_bulk_exports.cpython-313.pyc`
- `scripts/backfill-recurring-donation-contact-rollups.apex`
- `scripts/clear-unlinked-contact-rollups.apex`
- `scripts/tests/__pycache__/test_verify_rollups_from_bulk_exports.cpython-313.pyc`
- `scripts/tests/test_verify_rollups_from_bulk_exports.py`
- `scripts/verify-recurring-donation-contact-rollup-trigger.apex`
- `scripts/verify-recurring-donation-contact-rollups.apex`
- `scripts/verify_rollups_from_bulk_exports.py`
- `sfdx-project.json`

## Validation

Python sources and JSON/XML configuration are checked locally. Apex test classes are retained where present; executing them requires a compatible sandbox. No Salesforce query, deployment, backfill or record mutation was performed during preparation. See [SECURITY.md](SECURITY.md) for data handling.
