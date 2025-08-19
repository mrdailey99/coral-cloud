Case c = new Case(Subject = 'BUG- Backfill Test', Origin = 'Phone', Status = 'New', Priority = 'Medium', Type = 'Problem');
insert c;

BugHuntReportController.ReportPayload p = new BugHuntReportController.ReportPayload();
p.body = 'Test body';
p.subject = 'BUG- Backfill Test';
p.origin = 'Phone';
p.type = 'Problem';
p.priority = 'Medium';
p.description = 'Steps to repro...';
p.unsavedEmail = 'tester@example.com';
p.urgent = true;
p.recordId = c.Id;
p.username = 'cli-user';
p.includeTech = true;

Id rid = BugHuntReportController.createReport(p);
System.debug('NEW_REPORT: ' + rid);
Bug_Report__c br = [SELECT Id, Case__c, Subject__c, Origin__c, Type__c, Priority__c, SubmittedBy__c, Email__c FROM Bug_Report__c WHERE Id = :rid LIMIT 1];
System.debug('REPORT_FIELDS: ' + JSON.serialize(br));
