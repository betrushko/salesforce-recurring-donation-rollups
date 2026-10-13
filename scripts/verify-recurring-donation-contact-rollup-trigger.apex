List<Contact> visibleContacts = [
    SELECT
        Id,
        Total_Recurring_Donations__c,
        Open_Recurring_Donations__c,
        Closed_Recurring_Donations__c,
        Paused_Recurring_Donations__c,
        Closed_Active_Recurring_Donations__c,
        Closed_Passive_Recurring_Donations__c,
        Closed_Reactivation_RDs__c
    FROM Contact
    WHERE Open_Recurring_Donations__c > 0
    LIMIT 1
];

if (visibleContacts.isEmpty()) {
    System.debug(LoggingLevel.ERROR, 'ROLLUP_TRIGGER_VERIFICATION skipped=true reason=No visible Contact with open Recurring Donations found');
} else {
    Contact beforeContact = visibleContacts[0];

    npe03__Recurring_Donation__c candidate = [
        SELECT Id, npe03__Contact__c, npe03__Open_Ended_Status__c
        FROM npe03__Recurring_Donation__c
        WHERE npe03__Contact__c = :beforeContact.Id
        AND npe03__Open_Ended_Status__c IN ('Open', 'Operational')
        LIMIT 1
    ];

    Savepoint savepointBeforeTest = Database.setSavepoint();

    candidate.npe03__Open_Ended_Status__c = 'Paused';
    update candidate;

    Contact afterContact = [
        SELECT
            Id,
            Total_Recurring_Donations__c,
            Open_Recurring_Donations__c,
            Closed_Recurring_Donations__c,
            Paused_Recurring_Donations__c,
            Closed_Active_Recurring_Donations__c,
            Closed_Passive_Recurring_Donations__c,
            Closed_Reactivation_RDs__c
        FROM Contact
        WHERE Id = :candidate.npe03__Contact__c
    ];

    Boolean triggerRecalculated =
        afterContact.Total_Recurring_Donations__c == beforeContact.Total_Recurring_Donations__c &&
        afterContact.Open_Recurring_Donations__c == beforeContact.Open_Recurring_Donations__c - 1 &&
        afterContact.Paused_Recurring_Donations__c == beforeContact.Paused_Recurring_Donations__c + 1 &&
        afterContact.Closed_Recurring_Donations__c == beforeContact.Closed_Recurring_Donations__c &&
        afterContact.Closed_Active_Recurring_Donations__c == beforeContact.Closed_Active_Recurring_Donations__c &&
        afterContact.Closed_Passive_Recurring_Donations__c == beforeContact.Closed_Passive_Recurring_Donations__c &&
        afterContact.Closed_Reactivation_RDs__c == beforeContact.Closed_Reactivation_RDs__c;

    Database.rollback(savepointBeforeTest);

    System.debug(LoggingLevel.ERROR, 'ROLLUP_TRIGGER_VERIFICATION contactId=' + beforeContact.Id + ' recurringDonationId=' + candidate.Id + ' triggerRecalculated=' + triggerRecalculated);
    System.debug(LoggingLevel.ERROR, 'ROLLUP_TRIGGER_VERIFICATION before open=' + beforeContact.Open_Recurring_Donations__c + ' paused=' + beforeContact.Paused_Recurring_Donations__c + ' total=' + beforeContact.Total_Recurring_Donations__c);
    System.debug(LoggingLevel.ERROR, 'ROLLUP_TRIGGER_VERIFICATION during open=' + afterContact.Open_Recurring_Donations__c + ' paused=' + afterContact.Paused_Recurring_Donations__c + ' total=' + afterContact.Total_Recurring_Donations__c);
}
