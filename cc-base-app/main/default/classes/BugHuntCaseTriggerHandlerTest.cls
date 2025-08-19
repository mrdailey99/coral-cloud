@IsTest
private class BugHuntCaseTriggerHandlerTest {
    @IsTest
    static void createsBugReportFromCase() {
        Case c = new Case(Subject='BUG- Trigger Path', Origin='Phone', Type='Problem', Priority='Medium', Status='New');
        insert c;
        Bug_Report__c br = [SELECT Id, Case__c, Subject__c, Origin__c, Type__c, Priority__c, Description__c, SubmittedBy__c, Details__c
                             FROM Bug_Report__c WHERE Case__c = :c.Id LIMIT 1];
        System.assertEquals(c.Id, br.Case__c);
        System.assertEquals('BUG- Trigger Path', br.Subject__c);
        System.assertEquals('Phone', br.Origin__c);
        System.assertEquals('Problem', br.Type__c);
        System.assertEquals('Medium', br.Priority__c);
        System.assertNotEquals(null, br.Details__c);
        System.assert(br.Details__c.contains('After (saved)'));
    }

    @IsTest
    static void doesNotCreateForNonBugCases() {
        // This org enforces a validation rule that Subject must start with BUG-
        // Verify that such non-bug Cases never result in a Bug_Report__c by attempting insert and catching the validation error
        Case c = new Case(Subject='FYI- Not a Bug', Origin='Web', Type='Question', Priority='Low', Status='New');
        try {
            insert c;
            System.assert(false, 'Insert should have failed validation for non BUG- subject');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Subject must start with BUG-'));
        }
    }
}
