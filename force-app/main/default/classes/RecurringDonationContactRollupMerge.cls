global without sharing class RecurringDonationContactRollupMerge extends npsp.TDTM_Runnable {
    global override npsp.TDTM_Runnable.DmlWrapper run(
        List<SObject> newRecords,
        List<SObject> oldRecords,
        npsp.TDTM_Runnable.Action triggerAction,
        Schema.DescribeSObjectResult objectDescribe
    ) {
        npsp.TDTM_Runnable.DmlWrapper wrapper = new npsp.TDTM_Runnable.DmlWrapper();
        if (triggerAction != npsp.TDTM_Runnable.Action.AfterDelete) {
            return wrapper;
        }

        Set<Id> survivors = new Set<Id>();
        List<SObject> deletedContacts = oldRecords == null ? newRecords : oldRecords;
        if (deletedContacts != null) {
            for (SObject record : deletedContacts) {
                Id survivorId = ((Contact) record).MasterRecordId;
                if (survivorId != null) {
                    survivors.add(survivorId);
                }
            }
        }
        if (!survivors.isEmpty()) {
            // One job for the complete bulk invocation, after child reparenting has committed.
            // Scheduling failures must remain visible; silently skipping would leave stale counters.
            System.enqueueJob(new RecurringDonationContactRollupMergeJob(survivors));
        }
        return wrapper;
    }
}
