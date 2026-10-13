global without sharing class RecurringDonationContactRollupHandler extends npsp.TDTM_Runnable {
    // These values must match the actual picklist values in the target org.
    @TestVisible private static final Set<String> OPEN_STATUSES = new Set<String>{
        'Open',
        'Operational'
    };
    @TestVisible private static final Set<String> CLOSED_STATUSES = new Set<String>{
        'Closed',
        'Suspended'
    };
    @TestVisible private static final String PAUSED_STATUS = 'Paused';
    @TestVisible private static final String PASSIVE_CLOSURE_REASON = 'Regla de negocios';
    @TestVisible private static final Set<String> REACTIVATION_CLOSURE_REASONS = new Set<String>{
        'Reactivación',
        'Reactivacion'
    };

    global override npsp.TDTM_Runnable.DmlWrapper run(
        List<SObject> newRecords,
        List<SObject> oldRecords,
        npsp.TDTM_Runnable.Action triggerAction,
        Schema.DescribeSObjectResult objectDescribe
    ) {
        npsp.TDTM_Runnable.DmlWrapper wrapper = new npsp.TDTM_Runnable.DmlWrapper();

        if (!isSupportedAfterAction(triggerAction)) {
            return wrapper;
        }

        Set<Id> contactIds = collectAffectedContactIds(
            castRecurringDonations(newRecords),
            castRecurringDonations(oldRecords)
        );

        wrapper.objectsToUpdate = new List<SObject>();
        wrapper.objectsToUpdate.addAll(buildContactUpdates(contactIds));
        return wrapper;
    }

    @TestVisible
    private static Set<Id> collectAffectedContactIds(
        List<npe03__Recurring_Donation__c> newRecords,
        List<npe03__Recurring_Donation__c> oldRecords
    ) {
        Set<Id> contactIds = new Set<Id>();

        if (newRecords != null && oldRecords != null) {
            Map<Id, npe03__Recurring_Donation__c> oldById = new Map<Id, npe03__Recurring_Donation__c>();
            for (npe03__Recurring_Donation__c oldRecord : oldRecords) {
                if (oldRecord.Id != null) {
                    oldById.put(oldRecord.Id, oldRecord);
                }
            }
            Set<Id> newIds = new Set<Id>();
            for (Integer index = 0; index < newRecords.size(); index++) {
                npe03__Recurring_Donation__c newRecurringDonation = newRecords[index];
                npe03__Recurring_Donation__c oldRecurringDonation;
                if (newRecurringDonation.Id != null) {
                    newIds.add(newRecurringDonation.Id);
                    oldRecurringDonation = oldById.get(newRecurringDonation.Id);
                } else if (index < oldRecords.size() && oldRecords[index].Id == null) {
                    // Id-less records are supported for direct unit tests only.
                    oldRecurringDonation = oldRecords[index];
                }
                if (oldRecurringDonation == null || hasRollupRelevantChange(newRecurringDonation, oldRecurringDonation)) {
                    addContactId(contactIds, newRecurringDonation.npe03__Contact__c);
                    if (oldRecurringDonation != null) {
                        addContactId(contactIds, oldRecurringDonation.npe03__Contact__c);
                    }
                }
            }
            // Conservatively recalculate records missing from one side rather than dropping them.
            for (Integer index = 0; index < oldRecords.size(); index++) {
                npe03__Recurring_Donation__c oldRecord = oldRecords[index];
                if ((oldRecord.Id != null && !newIds.contains(oldRecord.Id))
                    || (oldRecord.Id == null && (index >= newRecords.size() || newRecords[index].Id != null))) {
                    addContactId(contactIds, oldRecord.npe03__Contact__c);
                }
            }
            return contactIds;
        }

        if (newRecords != null) {
            for (npe03__Recurring_Donation__c recurringDonation : newRecords) {
                addContactId(contactIds, recurringDonation.npe03__Contact__c);
            }
        }

        if (oldRecords != null) {
            for (npe03__Recurring_Donation__c recurringDonation : oldRecords) {
                addContactId(contactIds, recurringDonation.npe03__Contact__c);
            }
        }

        return contactIds;
    }

    private static Boolean hasRollupRelevantChange(
        npe03__Recurring_Donation__c newRecurringDonation,
        npe03__Recurring_Donation__c oldRecurringDonation
    ) {
        return newRecurringDonation.npe03__Contact__c != oldRecurringDonation.npe03__Contact__c
            || newRecurringDonation.npe03__Open_Ended_Status__c != oldRecurringDonation.npe03__Open_Ended_Status__c
            || newRecurringDonation.Motivo_de_cierre_de_DDRR__c != oldRecurringDonation.Motivo_de_cierre_de_DDRR__c;
    }

    private static void addContactId(Set<Id> contactIds, Id contactId) {
        if (contactId != null) {
            contactIds.add(contactId);
        }
    }

    private static Boolean isSupportedAfterAction(npsp.TDTM_Runnable.Action triggerAction) {
        return triggerAction == npsp.TDTM_Runnable.Action.AfterInsert
            || triggerAction == npsp.TDTM_Runnable.Action.AfterUpdate
            || triggerAction == npsp.TDTM_Runnable.Action.AfterDelete
            || triggerAction == npsp.TDTM_Runnable.Action.AfterUndelete;
    }

    private static List<npe03__Recurring_Donation__c> castRecurringDonations(List<SObject> records) {
        if (records == null) {
            return null;
        }

        List<npe03__Recurring_Donation__c> recurringDonations = new List<npe03__Recurring_Donation__c>();
        for (SObject record : records) {
            recurringDonations.add((npe03__Recurring_Donation__c) record);
        }
        return recurringDonations;
    }

    public static List<Contact> buildContactUpdates(Set<Id> contactIds) {
        List<Contact> contactsToUpdate = new List<Contact>();
        if (contactIds == null || contactIds.isEmpty()) {
            return contactsToUpdate;
        }

        Map<Id, Contact> currentContacts = new Map<Id, Contact>([
            SELECT Id, Total_Recurring_Donations__c, Open_Recurring_Donations__c,
                Closed_Recurring_Donations__c, Paused_Recurring_Donations__c,
                Closed_Active_Recurring_Donations__c, Closed_Passive_Recurring_Donations__c,
                Closed_Reactivation_RDs__c
            FROM Contact
            WHERE Id IN :contactIds
        ]);
        Set<Id> existingContactIds = currentContacts.keySet();
        if (existingContactIds.isEmpty()) {
            return contactsToUpdate;
        }

        Map<Id, RollupCounts> countsByContactId = new Map<Id, RollupCounts>();
        for (Id contactId : existingContactIds) {
            countsByContactId.put(contactId, new RollupCounts());
        }

        for (npe03__Recurring_Donation__c recurringDonation : [
            SELECT
                Id,
                npe03__Contact__c,
                npe03__Open_Ended_Status__c,
                Motivo_de_cierre_de_DDRR__c
            FROM npe03__Recurring_Donation__c
            WHERE npe03__Contact__c IN :existingContactIds
        ]) {
            RollupCounts counts = countsByContactId.get(recurringDonation.npe03__Contact__c);
            if (counts == null) {
                counts = new RollupCounts();
                countsByContactId.put(recurringDonation.npe03__Contact__c, counts);
            }

            counts.add(recurringDonation);
        }

        for (Id contactId : existingContactIds) {
            RollupCounts counts = countsByContactId.get(contactId);
            if (counts == null) {
                counts = new RollupCounts();
            }

            Contact updateRecord = new Contact(
                Id = contactId,
                Total_Recurring_Donations__c = counts.total,
                Open_Recurring_Donations__c = counts.openCount,
                Closed_Recurring_Donations__c = counts.closedCount,
                Paused_Recurring_Donations__c = counts.paused,
                Closed_Active_Recurring_Donations__c = counts.closedActive,
                Closed_Passive_Recurring_Donations__c = counts.closedPassive,
                Closed_Reactivation_RDs__c = counts.closedReactivation
            );
            if (!countersMatch(currentContacts.get(contactId), updateRecord)) {
                contactsToUpdate.add(updateRecord);
            }
        }

        // TDTM performs the DML from the returned DmlWrapper, keeping this handler focused on rollup calculation.
        return contactsToUpdate;
    }

    private static Boolean countersMatch(Contact current, Contact expected) {
        return current.Total_Recurring_Donations__c == expected.Total_Recurring_Donations__c
            && current.Open_Recurring_Donations__c == expected.Open_Recurring_Donations__c
            && current.Closed_Recurring_Donations__c == expected.Closed_Recurring_Donations__c
            && current.Paused_Recurring_Donations__c == expected.Paused_Recurring_Donations__c
            && current.Closed_Active_Recurring_Donations__c == expected.Closed_Active_Recurring_Donations__c
            && current.Closed_Passive_Recurring_Donations__c == expected.Closed_Passive_Recurring_Donations__c
            && current.Closed_Reactivation_RDs__c == expected.Closed_Reactivation_RDs__c;
    }

    private class RollupCounts {
        Integer total = 0;
        Integer openCount = 0;
        Integer closedCount = 0;
        Integer paused = 0;
        Integer closedActive = 0;
        Integer closedPassive = 0;
        Integer closedReactivation = 0;

        void add(npe03__Recurring_Donation__c recurringDonation) {
            total++;

            String status = recurringDonation.npe03__Open_Ended_Status__c;
            String closureReason = recurringDonation.Motivo_de_cierre_de_DDRR__c;

            // Business rules:
            // - Open and Operational are counted as open Recurring Donations.
            // - Closed and Suspended are counted as closed Recurring Donations.
            // - Paused is counted separately as inactive/paused.
            // - Active, Passive, and Reactivation classifications apply only to Closed/Suspended records.
            if (OPEN_STATUSES.contains(status)) {
                openCount++;
            } else if (CLOSED_STATUSES.contains(status)) {
                closedCount++;
                addClosedClassification(closureReason);
            } else if (PAUSED_STATUS == status) {
                paused++;
            }
        }

        private void addClosedClassification(String closureReason) {
            if (PASSIVE_CLOSURE_REASON == closureReason) {
                closedPassive++;
            } else if (REACTIVATION_CLOSURE_REASONS.contains(closureReason)) {
                closedReactivation++;
            } else {
                // Any other closure reason, including blank/null, is treated as active.
                closedActive++;
            }
        }
    }
}
