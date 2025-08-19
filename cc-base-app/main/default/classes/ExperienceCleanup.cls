public class ExperienceCleanup {
    public static void deleteDuplicateExperiences() {
        // Map to store the unique records to keep
        Map<Id, Experience__c> uniqueExperiences = new Map<Id, Experience__c>();
        
        // Query all Experience__c records and group by fields that define uniqueness
        List<AggregateResult> groupedResults = [
            SELECT MIN(Id) minId, COUNT(Id) recordCount, Name name, Type__c type
            FROM Experience__c
            GROUP BY Name, Type__c
            HAVING COUNT(Id) > 1
        ];
        
        // Collect IDs of duplicate records to delete
        Set<Id> duplicateIds = new Set<Id>();
        for (AggregateResult result : groupedResults) {
            Id minId = (Id) result.get('minId');
            String name = (String) result.get('name');
            String type = (String) result.get('type');
            
            // Query all records for this group to find duplicates
            List<Experience__c> duplicates = [
                SELECT Id
                FROM Experience__c
                WHERE Name = :name
                AND Type__c = :type
            ];
            
            for (Experience__c exp : duplicates) {
                if (exp.Id != minId) {
                    duplicateIds.add(exp.Id);
                }
            }
        }
        
        // Delete duplicate records
        if (!duplicateIds.isEmpty()) {
            try {
                delete [SELECT Id FROM Experience__c WHERE Id IN :duplicateIds];
            } catch (DmlException e) {
                System.debug('Error deleting duplicate experiences: ' + e.getMessage());
            }
        }
    }
}