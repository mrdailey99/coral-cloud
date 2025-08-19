Case c=new Case(Subject='BUG- Trigger E2E', Origin='Web', Type='Problem', Priority='Medium', Status='New');
insert c;
Bug_Report__c br=[SELECT Id, Case__c, Subject__c, Origin__c, Type__c, Priority__c FROM Bug_Report__c WHERE Case__c=:c.Id LIMIT 1];
System.debug('BR:'+br.Id+' subj='+br.Subject__c+' origin='+br.Origin__c+' type='+br.Type__c+' prio='+br.Priority__c);
