// Data repair: requires explicit approval and target-org confirmation before execution.
// Run after the normal backfill completes. Resets positive counters on Contacts without DRs.
Database.executeBatch(new RecurringDonationContactRollupBatch(true), 200);
