public without sharing class BugHuntBackfill {
    /**
     * Backfill missing custom fields on Bug_Report__c by parsing Details__c.
     * Returns the number of records updated.
     */
    @AuraEnabled
    public static Integer backfillFromDetails(Integer limitN) {
        Integer lim = (limitN == null || limitN <= 0) ? 200 : Math.min(limitN, 2000);
        List<Bug_Report__c> toUpdate = new List<Bug_Report__c>();

        List<Bug_Report__c> rows = [
            SELECT Id, Details__c, Case__c, CreatedDate,
                   Subject__c, Origin__c, Type__c, Priority__c, Urgent__c,
                   Email__c, SubmittedBy__c
            FROM Bug_Report__c
            WHERE (Subject__c = NULL OR Origin__c = NULL OR Type__c = NULL OR Priority__c = NULL OR SubmittedBy__c = NULL)
               OR (Subject__c = '' OR Origin__c = '' OR Type__c = '' OR Priority__c = '' OR SubmittedBy__c = '')
            ORDER BY CreatedDate DESC
            LIMIT :lim
        ];

        for (Bug_Report__c br : rows) {
            Map<String, String> parsed = String.isBlank(br.Details__c) ? new Map<String, String>() : parseDetails(br.Details__c);
            Boolean changed = false;

            if (String.isBlank(br.Subject__c) && parsed.containsKey('subject')) {
                String v = parsed.get('subject');
                if (!String.isBlank(v)) { br.Subject__c = v; changed = true; }
            }
            if (String.isBlank(br.Origin__c) && parsed.containsKey('origin')) {
                String v = parsed.get('origin');
                if (!String.isBlank(v)) { br.Origin__c = v; changed = true; }
            }
            if (String.isBlank(br.Type__c) && parsed.containsKey('type')) {
                String v = parsed.get('type');
                if (!String.isBlank(v)) { br.Type__c = v; changed = true; }
            }
            if (String.isBlank(br.Priority__c) && parsed.containsKey('priority')) {
                String v = parsed.get('priority');
                if (!String.isBlank(v)) { br.Priority__c = v; changed = true; }
            }
            if (parsed.containsKey('urgent')) {
                String u = parsed.get('urgent');
                if (u != null) {
                    br.Urgent__c = (u.toLowerCase() == 'true' || u == '1' || u.toLowerCase() == 'yes');
                    changed = true;
                }
            }
            if (String.isBlank(br.Email__c) && parsed.containsKey('email')) {
                String v = parsed.get('email');
                if (!String.isBlank(v)) { br.Email__c = v; changed = true; }
            }
            if (String.isBlank(br.SubmittedBy__c) && parsed.containsKey('user')) {
                String submitter = parsed.get('user');
                if (submitter != null) {
                    submitter = submitter.trim().left(80);
                    if (!String.isBlank(submitter)) {
                        br.SubmittedBy__c = submitter;
                        changed = true;
                    }
                }
            }

            // Try to set Case__c if missing by parsing RecordId from After(s) block
            if (br.Case__c == null && parsed.containsKey('recordid')) {
                String rid = parsed.get('recordid');
                if (!String.isBlank(rid)) {
                    // Validate 18-char Id format naively; if valid, assign
                    if (rid.length() == 18) {
                        br.Case__c = (Id)rid;
                        changed = true;
                    }
                }
            }

            // If still no Case__c, attempt a heuristic match: find a Case created within +/- 5 minutes with same subject
            if (br.Case__c == null && !String.isBlank(br.Subject__c)) {
                try {
                    Datetime startDt = br.CreatedDate.addMinutes(-5);
                    Datetime endDt = br.CreatedDate.addMinutes(5);
                    List<Case> candidates = [
                        SELECT Id FROM Case
                        WHERE Subject = :br.Subject__c AND CreatedDate >= :startDt AND CreatedDate <= :endDt
                        ORDER BY CreatedDate ASC LIMIT 1
                    ];
                    if (!candidates.isEmpty()) {
                        br.Case__c = candidates[0].Id;
                        changed = true;
                    }
                } catch (Exception ignore) {
                    // ignore matching errors
                }
            }

            // If subject is unavailable, try a time-only heuristic: pick nearest BUG-* Case within +/- 3 minutes
            if (br.Case__c == null && String.isBlank(br.Subject__c)) {
                try {
                    Datetime beforeStart = br.CreatedDate.addMinutes(-3);
                    Datetime beforeEnd = br.CreatedDate;
                    Case picked = null;
                    List<Case> prior = [
                        SELECT Id, Subject, Origin, Type, Priority
                        FROM Case
                        WHERE Subject LIKE 'BUG-%' AND CreatedDate >= :beforeStart AND CreatedDate <= :beforeEnd
                        ORDER BY CreatedDate DESC LIMIT 1
                    ];
                    if (!prior.isEmpty()) {
                        picked = prior[0];
                    } else {
                        Datetime afterStart = br.CreatedDate;
                        Datetime afterEnd = br.CreatedDate.addMinutes(3);
                        List<Case> afters = [
                            SELECT Id, Subject, Origin, Type, Priority
                            FROM Case
                            WHERE Subject LIKE 'BUG-%' AND CreatedDate >= :afterStart AND CreatedDate <= :afterEnd
                            ORDER BY CreatedDate ASC LIMIT 1
                        ];
                        if (!afters.isEmpty()) {
                            picked = afters[0];
                        }
                    }
                    if (picked != null) {
                        br.Case__c = picked.Id;
                        // opportunistically copy authoritative Case fields
                        if (String.isBlank(br.Subject__c) && !String.isBlank(picked.Subject)) { br.Subject__c = picked.Subject; }
                        if (String.isBlank(br.Origin__c) && !String.isBlank(picked.Origin))   { br.Origin__c  = picked.Origin; }
                        if (String.isBlank(br.Type__c) && !String.isBlank(picked.Type))       { br.Type__c    = picked.Type; }
                        if (String.isBlank(br.Priority__c) && !String.isBlank(picked.Priority)) { br.Priority__c = picked.Priority; }
                        changed = true;
                    }
                } catch (Exception ignore) {
                    // ignore matching errors
                }
            }

            // If still blank, try copying from related Case
            if (br.Case__c != null && (
                String.isBlank(br.Subject__c) || String.isBlank(br.Origin__c) || String.isBlank(br.Type__c) || String.isBlank(br.Priority__c)
            )) {
                Case c = [SELECT Subject, Origin, Type, Priority FROM Case WHERE Id = :br.Case__c LIMIT 1];
                if (String.isBlank(br.Subject__c))   { br.Subject__c = c.Subject; changed = true; }
                if (String.isBlank(br.Origin__c))    { br.Origin__c = c.Origin; changed = true; }
                if (String.isBlank(br.Type__c))      { br.Type__c = c.Type; changed = true; }
                if (String.isBlank(br.Priority__c))  { br.Priority__c = c.Priority; changed = true; }
            }

            if (changed) {
                toUpdate.add(br);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return toUpdate.size();
    }

    private static Map<String, String> parseDetails(String details) {
        Map<String, String> m = new Map<String, String>();
        for (String line : details.split('\n')) {
            Integer idx = line.indexOf(':');
            if (idx > 0) {
                String key = line.substring(0, idx).trim().toLowerCase();
                String val = line.substring(idx + 1).trim();
                if (!String.isBlank(key)) {
                    m.put(key, val);
                }
            }
        }
        return m;
    }
}
