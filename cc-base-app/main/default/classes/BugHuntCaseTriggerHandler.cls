public with sharing class BugHuntCaseTriggerHandler {
    public static void afterInsert(List<Case> newList) {
        if (newList == null || newList.isEmpty()) return;
        // Filter to BUG- subjects only
        List<Case> candidates = new List<Case>();
        for (Case c : newList) {
            if (c.Subject != null && c.Subject.startsWith('BUG-')) {
                candidates.add(c);
            }
        }
        if (candidates.isEmpty()) return;
        Set<Id> caseIds = new Set<Id>();
        for (Case c : candidates) caseIds.add(c.Id);
        // Skip Cases that already have a Bug_Report__c
        Set<Id> withReport = new Set<Id>();
        for (Bug_Report__c br : [SELECT Id, Case__c FROM Bug_Report__c WHERE Case__c IN :caseIds]) {
            withReport.add(br.Case__c);
        }
        List<Bug_Report__c> toInsert = new List<Bug_Report__c>();
        for (Case c : candidates) {
            if (withReport.contains(c.Id)) continue;
            Bug_Report__c br = new Bug_Report__c();
            br.Case__c = c.Id;
            br.Subject__c = safe(c.Subject);
            br.Origin__c = safe(c.Origin);
            br.Type__c = safe(c.Type);
            br.Priority__c = safe(c.Priority);
            br.Description__c = safe(c.Description);
            br.Urgent__c = false;
            br.Email__c = '';
            // br.SubmittedBy__c = 'guest';
            // Authoritative After (saved) block to help future backfills/repairs
            String lb = '\n';
            br.Details__c = '---' + lb + 'After (saved)' + lb +
                'RecordId: ' + String.valueOf(c.Id) + lb +
                'Subject: ' + safe(c.Subject) + lb +
                'Origin: ' + safe(c.Origin) + lb +
                'Type: ' + safe(c.Type) + lb +
                'Priority: ' + safe(c.Priority) + lb +
                'Description: ' + safe(c.Description);
            toInsert.add(br);
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private static String safe(String s) {
        return s == null ? '' : s;
    }
}
