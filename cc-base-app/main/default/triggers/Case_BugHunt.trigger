trigger Case_BugHunt on Case (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        BugHuntCaseTriggerHandler.afterInsert(Trigger.new);
    }
}
