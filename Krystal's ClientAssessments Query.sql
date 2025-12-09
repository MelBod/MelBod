WITH wh
AS (
SELECT f.ClientEpisodeOasisId
,f.SourceSystem

FROM dbo.factClientAssessments f(NOLOCK)

INNER JOIN dbo.dimEpisode de(NOLOCK) ON f.EpisodeKey = de.Id

INNER JOIN dbo.factEpisode fe(NOLOCK) ON fe.EpisodeKey = de.Id
AND fe.IsDeleted = 0

INNER JOIN dbo.dimQuestion dq(NOLOCK) ON f.QuestionKey = dq.Id

INNER JOIN dbo.dimServiceLineType dslt(NOLOCK) ON f.ServiceLineTypeKey = dslt.Id

INNER JOIN dimClientEpisodeVisit v(NOLOCK) ON f.ClientEpisodeVisitKey = v.id

LEFT OUTER JOIN dbo.dimOasisMOItem o(NOLOCK) ON dq.QuestionId = o.QuestionId

WHERE dslt.ServiceLineTypeId = 1
AND de.EpisodeStatus NOT IN (
'DELETED'
,'NON-ADMIT'
,'PENDING'
)
AND v.ScheduledVisitStatusDescription = 'COMPLETED'
AND o.OasisMONumber IN (
'GG0170Q1'
,'GG0170Q3'
,'GG0170Q4'
)
AND f.OasisAnswer = '0' -- patient is NOT wheelchair bound
AND f.ClientEpisodeOasisId IS NOT NULL
AND convert(DATE, f.visitDate) >= dateadd(day, - 180, convert(DATE, getdate()))

GROUP BY f.ClientEpisodeOasisId
,f.SourceSystem
)

SELECT DISTINCT f.ClientEpisodeVisitAssessmentId
,f.ClientEpisodeVisitAssementSeqNo
,f.PatientId
,f.EpisodeId
,f.Location
,f.BranchCode
,f.ClientEpisodeVisitId
,v.VisitAgentWorkerId AS WorkerId
,f.VisitDate
,f.ClientEpisodeOasisId
,his_ot.OasisTypeKey
,f.QuestionKey
,f.QuestionId
,o.OasisMONumber
,q.AssociatedMONumber
,f.OasisAnswer
,CASE 
WHEN wh.ClientEpisodeOasisId IS NOT NULL
THEN 0
ELSE 1
END AS Wheelchair
,CASE 
WHEN f.OasisAnswer IN (
'07'
,'88'
,'09'
,'10'
,'^'
,'-'
)
THEN 1
ELSE NULL
END AS 'ActivityNotAttempted'
,CASE 
WHEN wh.ClientEpisodeOasisId IS NOT NULL
AND o.OasisMONumber IN (
'GG0170R1'
,'GG0170R3'
,'GG0170R4'
) -- wheel question.  if patient NOT wheelchair bound do not evaluate wheel distance question
THEN NULL
WHEN wh.ClientEpisodeOasisId IS NULL
AND o.OasisMONumber IN (
'GG0170I1'
,'GG0170I3'
,'GG0170I4'
,'GG0170J1'
,'GG0170J3'
,'GG0170J4'
) -- walk questions. if patient IS wheelchair bound do not evaluate walk distance question
THEN NULL
WHEN f.OasisAnswer IN (
'07'
,'88'
,'09'
,'10'
,'^'
,'-'
)
THEN 1
ELSE NULL
END AS 'ActivityNotAttemptedAmb'
,f.SourceSystem

FROM dbo.factClientAssessments f(NOLOCK)

INNER JOIN dbo.dimEpisode de(NOLOCK) ON f.EpisodeKey = de.Id

INNER JOIN dbo.dimquestion q(NOLOCK) ON f.QuestionKey = q.Id

INNER JOIN dbo.factEpisode fe(NOLOCK) ON fe.EpisodeKey = de.Id
AND fe.IsDeleted = 0

INNER JOIN dbo.dimServiceLineType dslt(NOLOCK) ON f.ServiceLineTypeKey = dslt.Id

LEFT JOIN dbo.dimOasisMOItem o(NOLOCK) ON q.QuestionId = o.QuestionId

LEFT JOIN (
-- this is large table, only bring in the items needed; sourcesystemOasisId to get Oasis Type
SELECT h.SourceSystem
,h.ClientEpisodeOasisId
,h.OasisTypeKey

FROM dbo.factHospiceItemSets h(NOLOCK)
) his_ot ON his_ot.SourceSystem = f.SourceSystem
AND his_ot.ClientEpisodeOasisId = f.ClientEpisodeOasisId

LEFT JOIN vw_dimClientEpisodeVisitWithWorkerId v(NOLOCK) ON f.ClientEpisodeVisitId = v.ClientEpisodeVisitId
AND f.SourceSystem = v.SourceSystem

LEFT JOIN wh ON f.ClientEpisodeOasisId = wh.ClientEpisodeOasisId
AND f.SourceSystem = wh.SourceSystem

WHERE dslt.ServiceLineTypeId = 1
AND de.EpisodeStatus NOT IN (
'DELETED'
,'NON-ADMIT'
,'PENDING'
)
AND fe.IsDeleted = 0
AND v.ScheduledVisitStatusDescription = 'COMPLETED'
AND o.OasisMONumber IN (
-- SELFCARE START
'GG0130A1'
,'GG0130A3'
,'GG0130A4'
,-- EATING
'GG0130B1'
,'GG0130B3'
,'GG0130B4'
,-- ORAL HYGIENE
'GG0130C1'
,'GG0130C3'
,'GG0130C4'
,-- TOILET HYGIENE -- SELFCARE END
'GG0170A1'
,'GG0170A3'
,'GG0170A4'
,--ROLL L/R -- MOBILITY START
'GG0170C'
,'GG0170C1'
,'GG0170C3'
,'GG0170C4'
,-- LYING/SITTING BED
'GG0170D1'
,'GG0170D3'
,'GG0170D4'
,-- SIT TO STAND
'GG0170E1'
,'GG0170E3'
,'GG0170E4'
,-- CHAIR/BED TFR
'GG0170F1'
,'GG0170F3'
,'GG0170F4'
,-- TOILET TFR
'GG0170I1'
,'GG0170I3'
,'GG0170I4'
,-- WALK 10 FT
'GG0170J1'
,'GG0170J3'
,'GG0170J4'
,-- WALK 50 FT 2 TURNS
'GG0170R1'
,'GG0170R3'
,'GG0170R4'
,-- WHEEL 50 FT 2 TURNS -- MOBILITY END
'GG0170Q1'
,'GG0170Q3'
,'GG0170Q4'
) -- USE WHEELCHAIR/SCOOTER
--and f.ClientEpisodeOasisId is not null
AND convert(DATE, f.visitDate) >= dateadd(day, - 180, convert(DATE, getdate()))
