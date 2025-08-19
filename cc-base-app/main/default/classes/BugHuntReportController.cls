public without sharing class BugHuntReportController {
    
    public class ReportPayload {
        @AuraEnabled public String body { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String origin { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String unsavedEmail { get; set; }
        @AuraEnabled public Boolean urgent { get; set; }
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String username { get; set; }
        @AuraEnabled public Boolean includeTech { get; set; }
    }
    @AuraEnabled
    public static Id createReport(ReportPayload payload) {
        if (payload == null) {
            throw new AuraHandledException('Missing report payload');
        }
        if (!Schema.sObjectType.Bug_Report__c.isCreateable()) {
            throw new AuraHandledException('Not authorized to create bug reports');
        }
        try {
            System.debug('payload data JSON: ' + JSON.serialize(payload));
        } catch (Exception ignore) {
            System.debug('payload received but could not serialize');
        }
        
        // Normalize username for SubmittedBy__c (Text(80))
        String submitter = String.isBlank(payload.username) ? 'guest' : safe(payload.username).trim();
        submitter = submitter.left(80);
        System.debug('Normalized submitter: ' + submitter);
        // Guard: if there's no Case and no meaningful content, do not create a blank report
        Boolean hasCase = String.isNotBlank(payload.recordId);
        Boolean hasBody = String.isNotBlank(payload.body);
        Boolean hasAnyField =
            String.isNotBlank(payload.subject) ||
            String.isNotBlank(payload.origin) ||
            String.isNotBlank(payload.type) ||
            String.isNotBlank(payload.priority) ||
            String.isNotBlank(payload.description) ||
            String.isNotBlank(payload.unsavedEmail) ||
            (payload.urgent == true) ||
            (submitter != 'guest');
        if (!hasCase && !hasBody && !hasAnyField) {
            // No-op: avoid inserting an empty Bug_Report__c row
            return null;
        }

        // Reuse an existing Bug_Report__c for this Case when possible to avoid duplicates
        Bug_Report__c existing = null;
        if (String.isNotBlank(payload.recordId)) {
            try {
                existing = [SELECT Id, Case__c, Subject__c, Origin__c, Type__c, Priority__c, Description__c, Email__c, Urgent__c, SubmittedBy__c, Details__c
                            FROM Bug_Report__c WHERE Case__c = :payload.recordId ORDER BY CreatedDate DESC NULLS LAST LIMIT 1];
            } catch (Exception ignore) {
                // If not found or not accessible, we'll create a new one
            }
        }

        Bug_Report__c br = (existing == null) ? new Bug_Report__c() : existing;
        if (String.isNotBlank(payload.recordId)) {
            br.Case__c = payload.recordId;
        } else {
            // Fallback: attempt to find a recently created Case that matches the subject/time
            try {
                if (String.isNotBlank(payload.subject)) {
                    // Prefer exact subject match in the last hour
                    List<Case> exact = [
                        SELECT Id, Subject, Origin, Type, Priority
                        FROM Case
                        WHERE Subject = :payload.subject AND CreatedDate >= :System.now().addHours(-1)
                        ORDER BY CreatedDate DESC
                        LIMIT 1
                    ];
                    if (!exact.isEmpty()) {
                        br.Case__c = exact[0].Id;
                    }
                }
                if (br.Case__c == null && String.isNotBlank(payload.subject) && payload.subject != null && payload.subject.startsWith('BUG-')) {
                    // Secondary: any BUG- case from the last 10 minutes
                    List<Case> recentBug = [
                        SELECT Id, Subject, Origin, Type, Priority
                        FROM Case
                        WHERE Subject LIKE 'BUG-%' AND CreatedDate >= :System.now().addMinutes(-10)
                        ORDER BY CreatedDate DESC
                        LIMIT 1
                    ];
                    if (!recentBug.isEmpty()) {
                        br.Case__c = recentBug[0].Id;
                    }
                }
            } catch (Exception ignore) {
                // Best-effort fallback only
            }
        }

        // If we resolved a Case via fallback and didn't start with an existing report, try to reuse an existing report for that Case
        if (existing == null && br.Case__c != null) {
            try {
                Bug_Report__c reuse = [SELECT Id, Case__c, Subject__c, Origin__c, Type__c, Priority__c, Description__c, Email__c, Urgent__c, SubmittedBy__c, Details__c
                                        FROM Bug_Report__c WHERE Case__c = :br.Case__c ORDER BY CreatedDate DESC NULLS LAST LIMIT 1];
                if (reuse != null) {
                    existing = reuse;
                    br = existing;
                }
            } catch (Exception ignore) {
                // none existing, okay to insert below
            }
        }
        // Attribution: if the LWC provided a faux username, always use it; otherwise default to 'guest' only when empty
        if (String.isNotBlank(payload.username)) {
            br.SubmittedBy__c = submitter;
        } else if (String.isBlank(br.SubmittedBy__c)) {
            br.SubmittedBy__c = 'guest';
        }
        if (String.isNotBlank(payload.unsavedEmail) && String.isBlank(br.Email__c)) br.Email__c = safe(payload.unsavedEmail);
        if (String.isNotBlank(payload.subject)      && String.isBlank(br.Subject__c)) br.Subject__c = safe(payload.subject);
        if (String.isNotBlank(payload.type)         && String.isBlank(br.Type__c)) br.Type__c = safe(payload.type);
        if (String.isNotBlank(payload.priority)     && String.isBlank(br.Priority__c)) br.Priority__c = safe(payload.priority);
        if (String.isNotBlank(payload.origin)       && String.isBlank(br.Origin__c)) br.Origin__c = safe(payload.origin);
        if (String.isNotBlank(payload.description)  && String.isBlank(br.Description__c)) br.Description__c = safe(payload.description);
        // Urgent can only escalate to true; never downgrade
        if ((payload.urgent != null && payload.urgent == true)) br.Urgent__c = true;

        // Fallback: if any key fields are blank but we have a Case, copy from the Case
        if (br.Case__c != null && (
            String.isBlank(br.Subject__c) ||
            String.isBlank(br.Origin__c) ||
            String.isBlank(br.Type__c) ||
            String.isBlank(br.Priority__c)
        )) {
            Case c = [SELECT Subject, Origin, Type, Priority FROM Case WHERE Id = :br.Case__c LIMIT 1];
            if (String.isBlank(br.Subject__c))   br.Subject__c = safe(c.Subject);
            if (String.isBlank(br.Origin__c))    br.Origin__c = safe(c.Origin);
            if (String.isBlank(br.Type__c))      br.Type__c = safe(c.Type);
            if (String.isBlank(br.Priority__c))  br.Priority__c = safe(c.Priority);
        }
        String lb = '\n';
        String beforeBlock = (payload.body == null ? '' : payload.body);
        beforeBlock += lb + lb + '---' + lb + 'Before (user input)' + lb +
            'Subject: ' + safe(payload.subject) + lb +
            'Origin: ' + safe(payload.origin) + lb +
            'Type: ' + safe(payload.type) + lb +
            'Priority: ' + safe(payload.priority) + lb +
            'Description: ' + safe(payload.description) + lb +
            'Email: ' + safe(payload.unsavedEmail) + lb +
            'Urgent: ' + String.valueOf(payload.urgent) + lb +
            'User: ' + submitter;
        // Also append an After (saved) section with authoritative Case values, when available
        String afterBlock = '';
        if (br.Case__c != null) {
            try {
                Case c = [SELECT Subject, Origin, Type, Priority, Description FROM Case WHERE Id = :br.Case__c LIMIT 1];
                afterBlock += lb + lb + '---' + lb + 'After (saved)' + lb +
                    'RecordId: ' + String.valueOf(br.Case__c) + lb +
                    'Subject: ' + safe(c.Subject) + lb +
                    'Origin: ' + safe(c.Origin) + lb +
                    'Type: ' + safe(c.Type) + lb +
                    'Priority: ' + safe(c.Priority) + lb +
                    'Description: ' + safe(c.Description);
            } catch (Exception ignore) {
                // If Case is not accessible or query fails, skip the After section gracefully
            }
        }
        String existingDetails = String.valueOf(br.Details__c);
        String details = (existingDetails == null || existingDetails == 'null') ? '' : existingDetails;
        details = (details + (details == '' ? '' : (lb + lb)) + beforeBlock + afterBlock).left(32768);
        br.Details__c = details;

        if (existing == null) {
            insert br;
        } else {
            update br;
        }
        return br.Id;
    }

    @AuraEnabled(cacheable=true)
    public static Id getReportIdByCase(Id caseId) {
        if (caseId == null) return null;
        try {
            Bug_Report__c br = [SELECT Id FROM Bug_Report__c WHERE Case__c = :caseId ORDER BY CreatedDate DESC NULLS LAST LIMIT 1];
            return br != null ? br.Id : null;
        } catch (Exception ignore) {
            return null;
        }
    }

    private static String safe(String s) {
        return s == null ? '' : s;
    }
}
