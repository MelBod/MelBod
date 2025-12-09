-- How many filtered assessments?
SELECT COUNT(*) FROM dbo.factClientAssessments 
WHERE ServiceLineTypeId = 1 AND SourceSystem = 'Abode' AND isDeleted = 0;

-- How many visits in date range?
SELECT COUNT(*) FROM dbo.dimClientEpisodeVisit 
WHERE VisitDate BETWEEN '2025-08-01' AND '2025-09-01'
AND VisitDeletedFlag = 'N';

-- How many episodes?
SELECT COUNT(*) FROM dbo.dimEpisode;

-- How many dimQuestions?
SELECT COUNT(*) FROM dbo.dimQuestion;
