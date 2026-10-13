Integer checkedContacts = 0;
Integer mismatchedContacts = 0;
List<String> mismatches = new List<String>();

List<Contact> contacts = [
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
    WHERE Id IN (
        SELECT npe03__Contact__c
        FROM npe03__Recurring_Donation__c
        WHERE npe03__Contact__c != null
    )
    ORDER BY Total_Recurring_Donations__c DESC, LastModifiedDate DESC
];

// Separate selection for counters that remain positive after all DRs are removed.
contacts.addAll([
    SELECT Id, Total_Recurring_Donations__c, Open_Recurring_Donations__c,
        Closed_Recurring_Donations__c, Paused_Recurring_Donations__c,
        Closed_Active_Recurring_Donations__c, Closed_Passive_Recurring_Donations__c,
        Closed_Reactivation_RDs__c
    FROM Contact
    WHERE (Total_Recurring_Donations__c > 0 OR Open_Recurring_Donations__c > 0
        OR Closed_Recurring_Donations__c > 0 OR Paused_Recurring_Donations__c > 0
        OR Closed_Active_Recurring_Donations__c > 0 OR Closed_Passive_Recurring_Donations__c > 0
        OR Closed_Reactivation_RDs__c > 0)
    AND Id NOT IN (
        SELECT npe03__Contact__c FROM npe03__Recurring_Donation__c
        WHERE npe03__Contact__c != null
    )
]);

Set<Id> contactIds = new Set<Id>();
for (Contact contactRecord : contacts) {
    contactIds.add(contactRecord.Id);
}

Map<Id, List<npe03__Recurring_Donation__c>> donationsByContactId = new Map<Id, List<npe03__Recurring_Donation__c>>();
for (npe03__Recurring_Donation__c donation : [
    SELECT Id, npe03__Contact__c, npe03__Open_Ended_Status__c, Motivo_de_cierre_de_DDRR__c
    FROM npe03__Recurring_Donation__c
    WHERE npe03__Contact__c IN :contactIds
]) {
    if (!donationsByContactId.containsKey(donation.npe03__Contact__c)) {
        donationsByContactId.put(donation.npe03__Contact__c, new List<npe03__Recurring_Donation__c>());
    }
    donationsByContactId.get(donation.npe03__Contact__c).add(donation);
}

for (Contact contactRecord : contacts) {
    checkedContacts++;

    Integer expectedTotal = 0;
    Integer expectedOpen = 0;
    Integer expectedClosed = 0;
    Integer expectedPaused = 0;
    Integer expectedClosedActive = 0;
    Integer expectedClosedPassive = 0;
    Integer expectedClosedReactivation = 0;

    List<npe03__Recurring_Donation__c> relatedDonations = donationsByContactId.get(contactRecord.Id);
    if (relatedDonations == null) {
        relatedDonations = new List<npe03__Recurring_Donation__c>();
    }
    for (npe03__Recurring_Donation__c donation : relatedDonations) {
        expectedTotal++;

        String status = donation.npe03__Open_Ended_Status__c;
        String closeReason = donation.Motivo_de_cierre_de_DDRR__c;

        // Business rule: Open and Operational are active/open Recurring Donations.
        if (status == 'Open' || status == 'Operational') {
            expectedOpen++;
        }

        // Business rule: Closed and Suspended are closed Recurring Donations.
        if (status == 'Closed' || status == 'Suspended') {
            expectedClosed++;

            // Business rule: reactivation accepts the real API value and its historical unaccented variant.
            if (closeReason == 'Regla de negocios') {
                expectedClosedPassive++;
            } else if (closeReason == 'Reactivación' || closeReason == 'Reactivacion') {
                expectedClosedReactivation++;
            } else {
                expectedClosedActive++;
            }
        }

        // Business rule: Paused is inactive/paused.
        if (status == 'Paused') {
            expectedPaused++;
        }
    }

    Boolean matches =
        contactRecord.Total_Recurring_Donations__c == expectedTotal &&
        contactRecord.Open_Recurring_Donations__c == expectedOpen &&
        contactRecord.Closed_Recurring_Donations__c == expectedClosed &&
        contactRecord.Paused_Recurring_Donations__c == expectedPaused &&
        contactRecord.Closed_Active_Recurring_Donations__c == expectedClosedActive &&
        contactRecord.Closed_Passive_Recurring_Donations__c == expectedClosedPassive &&
        contactRecord.Closed_Reactivation_RDs__c == expectedClosedReactivation;

    if (!matches) {
        mismatchedContacts++;
        mismatches.add(
            contactRecord.Id +
            ' expected=(' + expectedTotal + ',' + expectedOpen + ',' + expectedClosed + ',' + expectedPaused + ',' + expectedClosedActive + ',' + expectedClosedPassive + ',' + expectedClosedReactivation + ')' +
            ' actual=(' + contactRecord.Total_Recurring_Donations__c + ',' + contactRecord.Open_Recurring_Donations__c + ',' + contactRecord.Closed_Recurring_Donations__c + ',' + contactRecord.Paused_Recurring_Donations__c + ',' + contactRecord.Closed_Active_Recurring_Donations__c + ',' + contactRecord.Closed_Passive_Recurring_Donations__c + ',' + contactRecord.Closed_Reactivation_RDs__c + ')'
        );
    }
}

System.debug(LoggingLevel.ERROR, 'ROLLUP_VERIFICATION checkedContacts=' + checkedContacts + ' mismatchedContacts=' + mismatchedContacts);
System.debug(LoggingLevel.ERROR, 'ROLLUP_VERIFICATION mismatches=' + String.join(mismatches, '\n'));
