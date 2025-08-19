public without sharing class BugHuntLeaderboardController {
    @AuraEnabled(cacheable=true)
    public static List<Bug_Report__c> getTopReports() {
        // Basic object access guard
        if (!Schema.sObjectType.Bug_Report__c.isAccessible()) {
            return new List<Bug_Report__c>();
        }
        return [
            SELECT Id, Name, SubmittedBy__c, Subject__c, Origin__c, Priority__c, Type__c, Urgent__c, Details__c, Description__c, Email__c, Case__c, Case__r.CaseNumber, Case__r.Reason, CreatedDate
            FROM Bug_Report__c
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Boolean getIsAdmin() {
        try {
            if (UserInfo.getUserType() == 'Guest') {
                return false;
            }
            // Avoid querying Profile if not readable
            if (!Schema.sObjectType.Profile.isAccessible()) {
                return false;
            }
            Id profileId = UserInfo.getProfileId();
            Profile p = [SELECT Name FROM Profile WHERE Id = :profileId LIMIT 1];
            return p != null && p.Name == 'System Administrator';
        } catch (Exception e) {
            return false;
        }
    }

    @AuraEnabled
    public static Integer clearAllReports() {
        if (!getIsAdmin()) {
            throw new AuraHandledException('Not authorized');
        }
        if (!Schema.sObjectType.Bug_Report__c.isDeletable()) {
            throw new AuraHandledException('Delete not permitted');
        }
        List<Bug_Report__c> toDelete = [SELECT Id FROM Bug_Report__c LIMIT 10000];
        Integer count = toDelete.size();
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        return count;
    }

    @AuraEnabled
    public static void deleteReport(Id reportId) {
        if (!getIsAdmin()) {
            throw new AuraHandledException('Not authorized');
        }
        if (reportId == null) {
            throw new AuraHandledException('Missing report id');
        }
        if (!Schema.sObjectType.Bug_Report__c.isDeletable()) {
            throw new AuraHandledException('Delete not permitted');
        }
        delete new Bug_Report__c(Id = reportId);
    }
}
