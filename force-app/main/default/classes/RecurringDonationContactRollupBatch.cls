global without sharing class RecurringDonationContactRollupBatch implements Database.Batchable<SObject> {
    private Boolean clearUnlinkedContacts;

    global RecurringDonationContactRollupBatch() {
        clearUnlinkedContacts = false;
    }

    global RecurringDonationContactRollupBatch(Boolean clearUnlinked) {
        clearUnlinkedContacts = clearUnlinked == true;
    }

    global Database.QueryLocator start(Database.BatchableContext context) {
        if (clearUnlinkedContacts) {
            // Separate pass: a semi-join cannot be combined with an OR across the two populations.
            return Database.getQueryLocator([
                SELECT Id FROM Contact
                WHERE (Total_Recurring_Donations__c > 0 OR Open_Recurring_Donations__c > 0
                    OR Closed_Recurring_Donations__c > 0 OR Paused_Recurring_Donations__c > 0
                    OR Closed_Active_Recurring_Donations__c > 0 OR Closed_Passive_Recurring_Donations__c > 0
                    OR Closed_Reactivation_RDs__c > 0)
                AND Id NOT IN (
                    SELECT npe03__Contact__c FROM npe03__Recurring_Donation__c
                    WHERE npe03__Contact__c != null
                )
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id
            FROM Contact
            WHERE Id IN (
                SELECT npe03__Contact__c
                FROM npe03__Recurring_Donation__c
                WHERE npe03__Contact__c != null
            )
        ]);
    }

    global void execute(Database.BatchableContext context, List<SObject> scope) {
        Set<Id> contactIds = new Set<Id>();
        for (SObject record : scope) {
            contactIds.add((Id) record.get('Id'));
        }

        // This backfill uses normal DML so any validation/configuration issue is visible in the batch error.
        List<Contact> updates = RecurringDonationContactRollupHandler.buildContactUpdates(contactIds);
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    global void finish(Database.BatchableContext context) {
        // No finish action required.
    }
}
