public without sharing class RecurringDonationContactRollupMergeJob implements Queueable {
    private Set<Id> survivorIds;

    public RecurringDonationContactRollupMergeJob(Set<Id> contactIds) {
        survivorIds = new Set<Id>();
        if (contactIds != null) {
            survivorIds.addAll(contactIds);
        }
    }

    public void execute(QueueableContext context) {
        if (survivorIds.isEmpty()) {
            return;
        }
        // A survivor can itself be merged again before this job executes.
        Set<Id> pending = new Set<Id>();
        pending.addAll(survivorIds);
        Set<Id> visited = new Set<Id>();
        Set<Id> currentSurvivors = new Set<Id>();
        while (!pending.isEmpty()) {
            List<Contact> candidates = [
                SELECT Id, IsDeleted, MasterRecordId FROM Contact WHERE Id IN :pending ALL ROWS
            ];
            visited.addAll(pending);
            pending.clear();
            for (Contact candidate : candidates) {
                if (!candidate.IsDeleted) {
                    currentSurvivors.add(candidate.Id);
                } else if (candidate.MasterRecordId != null && !visited.contains(candidate.MasterRecordId)) {
                    pending.add(candidate.MasterRecordId);
                }
            }
        }
        // Serialize concurrent merge repairs for the same surviving Contact.
        Set<Id> existingIds = new Map<Id, Contact>([
            SELECT Id FROM Contact WHERE Id IN :currentSurvivors FOR UPDATE
        ]).keySet();
        List<Contact> updates = RecurringDonationContactRollupHandler.buildContactUpdates(existingIds);
        if (!updates.isEmpty()) {
            update updates;
        }
        // Failures surface in AsyncApexJob; do not hide them behind partial DML.
    }
}
