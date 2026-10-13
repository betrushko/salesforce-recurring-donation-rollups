@IsTest
private class RecurringDonationContactRollupTest {
    private static final String STATUS_OPEN = 'Open';
    private static final String STATUS_OPERATIONAL = 'Operational';
    private static final String STATUS_CLOSED = 'Closed';
    private static final String STATUS_SUSPENDED = 'Suspended';
    private static final String STATUS_PAUSED = 'Paused';
    private static final String REASON_PASSIVE = 'Regla de negocios';
    private static final String REASON_REACTIVATION = 'Reactivación';
    private static final String REASON_ACTIVE = 'No Show';

    @IsTest
    static void reorderedUpdatesMatchById() {
        Id firstContact = '003000000000001';
        Id secondContact = '003000000000002';
        npe03__Recurring_Donation__c first = buildRecurringDonation(firstContact, STATUS_OPEN, null);
        String prefix = npe03__Recurring_Donation__c.SObjectType.getDescribe().getKeyPrefix();
        first.Id = (Id) (prefix + '000000000001');
        npe03__Recurring_Donation__c second = buildRecurringDonation(secondContact, STATUS_OPEN, null);
        second.Id = (Id) (prefix + '000000000002');
        System.assertEquals(new Set<Id>(), RecurringDonationContactRollupHandler.collectAffectedContactIds(
            new List<npe03__Recurring_Donation__c>{ second, first },
            new List<npe03__Recurring_Donation__c>{ first, second }
        ), 'Reordering unchanged records must not look like a contact transfer.');
        System.assertEquals(new Set<Id>{ secondContact }, RecurringDonationContactRollupHandler.collectAffectedContactIds(
            new List<npe03__Recurring_Donation__c>{ first },
            new List<npe03__Recurring_Donation__c>{ first, second }
        ), 'An unmatched old record must not be silently omitted.');
    }

    @IsTest
    static void legacyReactivationAndNullAreClassified() {
        Contact contact = createContact('Legacy and null reasons');
        insert new List<npe03__Recurring_Donation__c>{
            buildRecurringDonation(contact.Id, STATUS_CLOSED, 'Reactivacion'),
            buildRecurringDonation(contact.Id, STATUS_SUSPENDED, REASON_REACTIVATION),
            buildRecurringDonation(contact.Id, STATUS_CLOSED, null)
        };
        runHandlerAfterInsert(queryRecurringDonations(contact.Id));
        Contact result = getContact(contact.Id);
        System.assertEquals(2, result.Closed_Reactivation_RDs__c);
        System.assertEquals(1, result.Closed_Active_Recurring_Donations__c);
        System.assertEquals(3, result.Closed_Recurring_Donations__c);
    }

    @IsTest
    static void unchangedCountersProduceNoUpdates() {
        Contact contact = createContact('No redundant writes');
        insert buildRecurringDonation(contact.Id, STATUS_OPEN, null);
        runHandlerAfterInsert(queryRecurringDonations(contact.Id));
        System.assertEquals(0, RecurringDonationContactRollupHandler.buildContactUpdates(
            new Set<Id>{ contact.Id }
        ).size(), 'Correct counters must not generate another Contact write.');
    }

    @IsTest
    static void batchClearsUnlinkedStaleCounters() {
        Contact contact = createContact('Unlinked stale counters');
        update new Contact(Id = contact.Id, Total_Recurring_Donations__c = 2,
            Open_Recurring_Donations__c = 1, Closed_Recurring_Donations__c = 1);
        Test.startTest();
        Database.executeBatch(new RecurringDonationContactRollupBatch(true), 200);
        Test.stopTest();
        Contact result = getContact(contact.Id);
        System.assertEquals(0, result.Total_Recurring_Donations__c);
        System.assertEquals(0, result.Open_Recurring_Donations__c);
        System.assertEquals(0, result.Closed_Recurring_Donations__c);
        System.assertEquals(0, result.Closed_Reactivation_RDs__c);
    }

    @IsTest
    static void mergeJobFollowsSubsequentMerge() {
        configureTestHandlers(false);
        Contact first = createContact('First survivor');
        Contact loser = createContact('First loser');
        Contact finalSurvivor = createContact('Final survivor');
        insert buildRecurringDonation(loser.Id, STATUS_OPEN, null);
        Test.startTest();
        System.enqueueJob(new RecurringDonationContactRollupMergeJob(new Set<Id>{ first.Id }));
        merge first loser;
        merge finalSurvivor first;
        Test.stopTest();
        System.assertEquals(1, getContact(finalSurvivor.Id).Total_Recurring_Donations__c);
        System.assertEquals(1, getContact(finalSurvivor.Id).Open_Recurring_Donations__c);
    }

    @IsTest
    static void rolledBackMergeDoesNotRepairSurvivor() {
        configureTestHandlers();
        Contact survivor = createContact('Rollback survivor');
        Contact loser = createContact('Rollback loser');
        insert buildRecurringDonation(loser.Id, STATUS_OPEN, null);
        // A distinctive value makes an incorrectly retained repair job observable.
        update new Contact(Id = survivor.Id, Total_Recurring_Donations__c = 99);
        Test.startTest();
        Savepoint beforeMerge = Database.setSavepoint();
        merge survivor loser;
        Database.rollback(beforeMerge);
        Test.stopTest();
        System.assertEquals(99, getContact(survivor.Id).Total_Recurring_Donations__c,
            'The rolled-back merge must also roll back its queued repair.');
        System.assertEquals(1, getContact(loser.Id).Total_Recurring_Donations__c);
    }

    @IsTest
    static void tdtmDonationLifecycleWorksThroughDml() {
        configureTestHandlers();
        Contact contact = createContact('TDTM lifecycle');
        Contact destination = createContact('TDTM destination');
        npe03__Recurring_Donation__c donation = buildRecurringDonation(contact.Id, STATUS_OPEN, null);
        Test.startTest();
        insert donation;
        System.assertEquals(1, getContact(contact.Id).Open_Recurring_Donations__c);
        donation.npe03__Open_Ended_Status__c = STATUS_CLOSED;
        donation.Motivo_de_cierre_de_DDRR__c = REASON_REACTIVATION;
        update donation;
        System.assertEquals(1, getContact(contact.Id).Closed_Reactivation_RDs__c);
        donation.npe03__Contact__c = destination.Id;
        update donation;
        System.assertEquals(0, getContact(contact.Id).Total_Recurring_Donations__c);
        System.assertEquals(1, getContact(destination.Id).Total_Recurring_Donations__c);
        delete donation;
        System.assertEquals(0, getContact(destination.Id).Total_Recurring_Donations__c);
        undelete donation;
        System.assertEquals(1, getContact(destination.Id).Closed_Reactivation_RDs__c);
        Test.stopTest();
    }

    @IsTest
    static void mergeRepairsEmptySurvivorThroughTdtm() {
        configureTestHandlers();
        Contact survivor = createContact('Empty merge survivor');
        Contact loser = createContact('Merge loser');
        insert buildRecurringDonation(loser.Id, STATUS_OPEN, null);
        Test.startTest();
        merge survivor loser;
        Test.stopTest();
        Contact result = getContact(survivor.Id);
        System.assertEquals(1, result.Total_Recurring_Donations__c);
        System.assertEquals(1, result.Open_Recurring_Donations__c);
        System.assertEquals(0, result.Closed_Reactivation_RDs__c);
    }

    @IsTest
    static void mergeRepairsCombinedSurvivorThroughTdtm() {
        configureTestHandlers();
        Contact survivor = createContact('Combined merge survivor');
        Contact loser = createContact('Combined merge loser');
        insert new List<npe03__Recurring_Donation__c>{
            buildRecurringDonation(survivor.Id, STATUS_CLOSED, REASON_PASSIVE),
            buildRecurringDonation(loser.Id, STATUS_OPEN, null)
        };
        Test.startTest();
        merge survivor loser;
        Test.stopTest();
        Contact result = getContact(survivor.Id);
        System.assertEquals(2, result.Total_Recurring_Donations__c);
        System.assertEquals(1, result.Open_Recurring_Donations__c);
        System.assertEquals(1, result.Closed_Passive_Recurring_Donations__c);
    }

    @IsTest
    static void ordinaryDeleteDoesNotScheduleMergeJob() {
        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        new RecurringDonationContactRollupMerge().run(null,
            new List<SObject>{ new Contact(Id = '003000000000001') },
            npsp.TDTM_Runnable.Action.AfterDelete, Contact.SObjectType.getDescribe());
        System.assertEquals(jobsBefore, Limits.getQueueableJobs());
        Test.stopTest();
    }

    @IsTest
    static void bulkMergeSchedulesOneRepairJob() {
        Contact survivor = createContact('Bulk survivor');
        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        new RecurringDonationContactRollupMerge().run(null,
            new List<SObject>{
                mergedContact('003000000000001', survivor.Id),
                mergedContact('003000000000002', survivor.Id)
            }, npsp.TDTM_Runnable.Action.AfterDelete, Contact.SObjectType.getDescribe());
        System.assertEquals(jobsBefore + 1, Limits.getQueueableJobs());
        Test.stopTest();
        System.assertEquals(0, getContact(survivor.Id).Total_Recurring_Donations__c);
    }

    private static void configureTestHandlers() {
        configureTestHandlers(true);
    }

    private static void configureTestHandlers(Boolean includeMerge) {
        List<npsp__Trigger_Handler__c> handlers = npsp.TDTM_Config_API.getCachedRecords();
        for (npsp__Trigger_Handler__c handler : handlers) {
            if (handler.npsp__Class__c == 'RecurringDonationContactRollupHandler'
                || handler.npsp__Class__c == 'RecurringDonationContactRollupMerge') {
                handler.npsp__Active__c = false;
            }
        }
        handlers.add(new npsp__Trigger_Handler__c(
            npsp__Class__c = 'RecurringDonationContactRollupHandler',
            npsp__Object__c = 'npe03__Recurring_Donation__c',
            npsp__Trigger_Action__c = 'AfterInsert;AfterUpdate;AfterDelete;AfterUndelete',
            npsp__Active__c = true, npsp__Asynchronous__c = false, npsp__Load_Order__c = 99
        ));
        if (includeMerge) {
            handlers.add(new npsp__Trigger_Handler__c(
                npsp__Class__c = 'RecurringDonationContactRollupMerge',
                npsp__Object__c = 'Contact', npsp__Trigger_Action__c = 'AfterDelete',
                npsp__Active__c = true, npsp__Asynchronous__c = false, npsp__Load_Order__c = 99
            ));
        }
    }

    private static Contact mergedContact(Id recordId, Id survivorId) {
        // MasterRecordId is read-only; simulate the platform's after-delete snapshot without DML.
        return (Contact) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'Id' => recordId, 'MasterRecordId' => survivorId
        }), Contact.class);
    }

    @IsTest
    static void unchangedRollupFieldsSkipRecalculation() {
        Id contactId = '003000000000001';
        npe03__Recurring_Donation__c beforeRecord = buildRecurringDonation(contactId, STATUS_OPEN, null);
        npe03__Recurring_Donation__c afterRecord = beforeRecord.clone(false, true, false, false);
        afterRecord.npe03__Amount__c = 20;
        Set<Id> affected = RecurringDonationContactRollupHandler.collectAffectedContactIds(
            new List<npe03__Recurring_Donation__c>{ afterRecord },
            new List<npe03__Recurring_Donation__c>{ beforeRecord }
        );
        System.assertEquals(0, affected.size(), 'Amount-only updates should not recalculate counters.');
    }

    @IsTest
    static void relevantChangesSelectBothContacts() {
        Id oldContactId = '003000000000001';
        Id newContactId = '003000000000002';
        npe03__Recurring_Donation__c beforeRecord = buildRecurringDonation(oldContactId, STATUS_OPEN, null);
        npe03__Recurring_Donation__c afterRecord = beforeRecord.clone(false, true, false, false);
        afterRecord.npe03__Contact__c = newContactId;
        System.assertEquals(new Set<Id>{ oldContactId, newContactId },
            RecurringDonationContactRollupHandler.collectAffectedContactIds(
                new List<npe03__Recurring_Donation__c>{ afterRecord },
                new List<npe03__Recurring_Donation__c>{ beforeRecord }
            ), 'Moving a donation must select both contacts.');

        afterRecord.npe03__Contact__c = null;
        System.assertEquals(new Set<Id>{ oldContactId },
            RecurringDonationContactRollupHandler.collectAffectedContactIds(
                new List<npe03__Recurring_Donation__c>{ afterRecord },
                new List<npe03__Recurring_Donation__c>{ beforeRecord }
            ), 'Removing the lookup must still reset the previous contact.');
    }

    @IsTest
    static void statusAndReasonChangesSelectContact() {
        Id contactId = '003000000000001';
        npe03__Recurring_Donation__c beforeRecord = buildRecurringDonation(contactId, STATUS_CLOSED, REASON_ACTIVE);
        npe03__Recurring_Donation__c afterRecord = beforeRecord.clone(false, true, false, false);
        afterRecord.Motivo_de_cierre_de_DDRR__c = REASON_REACTIVATION;
        System.assertEquals(new Set<Id>{ contactId },
            RecurringDonationContactRollupHandler.collectAffectedContactIds(
                new List<npe03__Recurring_Donation__c>{ afterRecord },
                new List<npe03__Recurring_Donation__c>{ beforeRecord }
            ), 'A closure reason change alone must recalculate classification.');

        afterRecord.Motivo_de_cierre_de_DDRR__c = REASON_ACTIVE;
        afterRecord.npe03__Open_Ended_Status__c = STATUS_PAUSED;
        System.assertEquals(new Set<Id>{ contactId },
            RecurringDonationContactRollupHandler.collectAffectedContactIds(
                new List<npe03__Recurring_Donation__c>{ afterRecord },
                new List<npe03__Recurring_Donation__c>{ beforeRecord }
            ), 'A status change alone must recalculate the contact.');
    }

    @IsTest
    static void bulkFilterIncludesOnlyChangedContacts() {
        Id changedContactId = '003000000000001';
        Id unchangedContactId = '003000000000002';
        npe03__Recurring_Donation__c changedBefore = buildRecurringDonation(changedContactId, STATUS_OPEN, null);
        npe03__Recurring_Donation__c changedAfter = buildRecurringDonation(changedContactId, STATUS_PAUSED, null);
        npe03__Recurring_Donation__c unchanged = buildRecurringDonation(unchangedContactId, STATUS_OPEN, null);
        System.assertEquals(new Set<Id>{ changedContactId },
            RecurringDonationContactRollupHandler.collectAffectedContactIds(
                new List<npe03__Recurring_Donation__c>{ changedAfter, unchanged },
                new List<npe03__Recurring_Donation__c>{ changedBefore, unchanged }
            ), 'Mixed updates must exclude contacts without relevant changes.');
    }

    @IsTest
    static void insertOpenAndOperationalRecurringDonations() {
        Contact contact = createContact('Open Operational');

        Test.startTest();
        insert new List<npe03__Recurring_Donation__c>{
            buildRecurringDonation(contact.Id, STATUS_OPEN, null),
            buildRecurringDonation(contact.Id, STATUS_OPERATIONAL, null)
        };
        runHandlerAfterInsert(queryRecurringDonations(contact.Id));
        Test.stopTest();

        Contact result = getContact(contact.Id);
        System.assertEquals(2, result.Total_Recurring_Donations__c, 'Total count should include all Recurring Donations.');
        System.assertEquals(2, result.Open_Recurring_Donations__c, 'Open and Operational should both count as open.');
        System.assertEquals(0, result.Closed_Recurring_Donations__c, 'No closed Recurring Donations were inserted.');
        System.assertEquals(0, result.Paused_Recurring_Donations__c, 'No paused Recurring Donations were inserted.');
    }

    @IsTest
    static void updateOpenToClosedAndSuspendedRecalculatesClosedCounts() {
        Contact contact = createContact('Closed Suspended');
        npe03__Recurring_Donation__c closedDonation = buildRecurringDonation(contact.Id, STATUS_OPEN, null);
        npe03__Recurring_Donation__c suspendedDonation = buildRecurringDonation(contact.Id, STATUS_OPEN, null);
        insert new List<npe03__Recurring_Donation__c>{ closedDonation, suspendedDonation };
        List<npe03__Recurring_Donation__c> beforeRecords = queryRecurringDonations(contact.Id);

        Test.startTest();
        closedDonation.npe03__Open_Ended_Status__c = STATUS_CLOSED;
        closedDonation.Motivo_de_cierre_de_DDRR__c = REASON_ACTIVE;
        suspendedDonation.npe03__Open_Ended_Status__c = STATUS_SUSPENDED;
        suspendedDonation.Motivo_de_cierre_de_DDRR__c = REASON_ACTIVE;
        update new List<npe03__Recurring_Donation__c>{ closedDonation, suspendedDonation };
        runHandlerAfterUpdate(
            queryRecurringDonations(contact.Id),
            beforeRecords
        );
        Test.stopTest();

        Contact result = getContact(contact.Id);
        System.assertEquals(2, result.Total_Recurring_Donations__c, 'Total should stay unchanged after status updates.');
        System.assertEquals(0, result.Open_Recurring_Donations__c, 'Open count should decrease after closing both records.');
        System.assertEquals(2, result.Closed_Recurring_Donations__c, 'Closed and Suspended should both count as closed.');
        System.assertEquals(2, result.Closed_Active_Recurring_Donations__c, 'Other closure reasons should count as active.');
    }

    @IsTest
    static void updateOpenToPausedRecalculatesPausedCount() {
        Contact contact = createContact('Paused');
        npe03__Recurring_Donation__c recurringDonation = buildRecurringDonation(contact.Id, STATUS_OPEN, null);
        insert recurringDonation;
        List<npe03__Recurring_Donation__c> beforeRecords = queryRecurringDonations(contact.Id);

        Test.startTest();
        recurringDonation.npe03__Open_Ended_Status__c = STATUS_PAUSED;
        update recurringDonation;
        runHandlerAfterUpdate(
            queryRecurringDonations(contact.Id),
            beforeRecords
        );
        Test.stopTest();

        Contact result = getContact(contact.Id);
        System.assertEquals(1, result.Total_Recurring_Donations__c, 'Total should include paused Recurring Donations.');
        System.assertEquals(0, result.Open_Recurring_Donations__c, 'Paused should not count as open.');
        System.assertEquals(1, result.Paused_Recurring_Donations__c, 'Paused status should count separately.');
    }

    @IsTest
    static void closedClassificationsAreMutuallyExclusive() {
        Contact contact = createContact('Classifications');

        Test.startTest();
        insert new List<npe03__Recurring_Donation__c>{
            buildRecurringDonation(contact.Id, STATUS_CLOSED, REASON_PASSIVE),
            buildRecurringDonation(contact.Id, STATUS_CLOSED, REASON_REACTIVATION),
            buildRecurringDonation(contact.Id, STATUS_CLOSED, REASON_ACTIVE)
        };
        runHandlerAfterInsert(queryRecurringDonations(contact.Id));
        Test.stopTest();

        Contact result = getContact(contact.Id);
        System.assertEquals(3, result.Closed_Recurring_Donations__c, 'All three records are closed.');
        System.assertEquals(1, result.Closed_Passive_Recurring_Donations__c, 'Regla de negocios should count as passive.');
        System.assertEquals(1, result.Closed_Reactivation_RDs__c, 'Reactivacion should count separately.');
        System.assertEquals(1, result.Closed_Active_Recurring_Donations__c, 'Other closure reasons should count as active.');
    }

    @IsTest
    static void changingContactRecalculatesOldAndNewContacts() {
        Contact oldContact = createContact('Old Contact');
        Contact newContact = createContact('New Contact');
        npe03__Recurring_Donation__c recurringDonation = buildRecurringDonation(oldContact.Id, STATUS_OPEN, null);
        insert recurringDonation;
        List<npe03__Recurring_Donation__c> beforeRecords = queryRecurringDonations(oldContact.Id);

        Test.startTest();
        recurringDonation.npe03__Contact__c = newContact.Id;
        update recurringDonation;
        runHandlerAfterUpdate(
            queryRecurringDonations(newContact.Id),
            beforeRecords
        );
        Test.stopTest();

        Contact oldResult = getContact(oldContact.Id);
        Contact newResult = getContact(newContact.Id);
        System.assertEquals(0, oldResult.Total_Recurring_Donations__c, 'Old Contact should be reset to zero.');
        System.assertEquals(1, newResult.Total_Recurring_Donations__c, 'New Contact should receive the moved Recurring Donation.');
        System.assertEquals(1, newResult.Open_Recurring_Donations__c, 'Moved open Recurring Donation should count for the new Contact.');
    }

    @IsTest
    static void deleteAndUndeleteRecalculateCounts() {
        Contact contact = createContact('Delete Undelete');
        npe03__Recurring_Donation__c recurringDonation = buildRecurringDonation(contact.Id, STATUS_OPEN, null);
        insert recurringDonation;
        runHandlerAfterInsert(queryRecurringDonations(contact.Id));

        delete recurringDonation;
        runHandlerAfterDelete(new List<npe03__Recurring_Donation__c>{
            new npe03__Recurring_Donation__c(npe03__Contact__c = contact.Id)
        });

        Contact afterDelete = getContact(contact.Id);
        System.assertEquals(0, afterDelete.Total_Recurring_Donations__c, 'Contact should be reset after the only Recurring Donation is deleted.');
        System.assertEquals(0, afterDelete.Open_Recurring_Donations__c, 'Open count should be reset after delete.');

        undelete recurringDonation;
        runHandlerAfterUndelete(queryRecurringDonations(contact.Id));

        Contact afterUndelete = getContact(contact.Id);
        System.assertEquals(1, afterUndelete.Total_Recurring_Donations__c, 'Undelete should restore the total count.');
        System.assertEquals(1, afterUndelete.Open_Recurring_Donations__c, 'Undelete should restore the open count.');
    }

    @IsTest
    static void batchBackfillsExistingContacts() {
        Contact contact = createContact('Backfill');
        insert buildRecurringDonation(contact.Id, STATUS_CLOSED, REASON_PASSIVE);

        Test.startTest();
        Database.executeBatch(new RecurringDonationContactRollupBatch(), 50);
        Test.stopTest();

        Contact result = getContact(contact.Id);
        System.assertEquals(1, result.Total_Recurring_Donations__c, 'Backfill should calculate total Recurring Donations.');
        System.assertEquals(1, result.Closed_Recurring_Donations__c, 'Backfill should calculate closed Recurring Donations.');
        System.assertEquals(1, result.Closed_Passive_Recurring_Donations__c, 'Backfill should calculate passive closures.');
    }

    private static Contact createContact(String lastName) {
        Contact contact = new Contact(LastName = lastName);
        insert contact;
        return contact;
    }

    private static npe03__Recurring_Donation__c buildRecurringDonation(
        Id contactId,
        String status,
        String closureReason
    ) {
        npe03__Recurring_Donation__c recurringDonation = new npe03__Recurring_Donation__c(
            Name = 'Test Recurring Donation',
            npe03__Contact__c = contactId,
            npe03__Amount__c = 10,
            npe03__Date_Established__c = Date.today(),
            npe03__Installment_Period__c = 'Monthly',
            npe03__Schedule_Type__c = 'Multiply By',
            npe03__Open_Ended_Status__c = status
        );
        recurringDonation.Motivo_de_cierre_de_DDRR__c = closureReason;
        return recurringDonation;
    }

    private static Contact getContact(Id contactId) {
        return [
            SELECT
                Total_Recurring_Donations__c,
                Open_Recurring_Donations__c,
                Closed_Recurring_Donations__c,
                Paused_Recurring_Donations__c,
                Closed_Active_Recurring_Donations__c,
                Closed_Passive_Recurring_Donations__c,
                Closed_Reactivation_RDs__c
            FROM Contact
            WHERE Id = :contactId
        ];
    }

    private static List<npe03__Recurring_Donation__c> queryRecurringDonations(Id contactId) {
        return [
            SELECT Id, npe03__Contact__c, npe03__Open_Ended_Status__c, Motivo_de_cierre_de_DDRR__c
            FROM npe03__Recurring_Donation__c
            WHERE npe03__Contact__c = :contactId
            ORDER BY Id
        ];
    }

    private static void runHandlerAfterInsert(List<npe03__Recurring_Donation__c> newRecords) {
        runHandler(newRecords, null, npsp.TDTM_Runnable.Action.AfterInsert);
    }

    private static void runHandlerAfterUpdate(
        List<npe03__Recurring_Donation__c> newRecords,
        List<npe03__Recurring_Donation__c> oldRecords
    ) {
        runHandler(newRecords, oldRecords, npsp.TDTM_Runnable.Action.AfterUpdate);
    }

    private static void runHandlerAfterDelete(List<npe03__Recurring_Donation__c> oldRecords) {
        runHandler(null, oldRecords, npsp.TDTM_Runnable.Action.AfterDelete);
    }

    private static void runHandlerAfterUndelete(List<npe03__Recurring_Donation__c> newRecords) {
        runHandler(newRecords, null, npsp.TDTM_Runnable.Action.AfterUndelete);
    }

    private static void runHandler(
        List<npe03__Recurring_Donation__c> newRecords,
        List<npe03__Recurring_Donation__c> oldRecords,
        npsp.TDTM_Runnable.Action action
    ) {
        npsp.TDTM_Runnable.DmlWrapper wrapper = new RecurringDonationContactRollupHandler().run(
            toSObjects(newRecords),
            toSObjects(oldRecords),
            action,
            npe03__Recurring_Donation__c.SObjectType.getDescribe()
        );

        if (wrapper.objectsToUpdate != null && !wrapper.objectsToUpdate.isEmpty()) {
            update wrapper.objectsToUpdate;
        }
    }

    private static List<SObject> toSObjects(List<npe03__Recurring_Donation__c> records) {
        if (records == null) {
            return null;
        }

        List<SObject> sObjects = new List<SObject>();
        sObjects.addAll(records);
        return sObjects;
    }
}
