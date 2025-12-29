DECLARE @StartDate DATE = DATEFROMPARTS(YEAR(DATEADD(MONTH, - 6, GETDATE())), MONTH(DATEADD(MONTH, - 6, GETDATE())), 1);

DECLARE @EndDate DATE = DATEADD(DAY, 1, CAST(GETDATE() AS DATE));

WITH base
AS (
     SELECT dv.WorkerId
          ,CONCAT (
               dv.WorkerNameLast
               ,', '
               ,dv.WorkerNameFirst
               ) AS WorkerName
          ,fvt.VisitDate
          ,dv.VisitId
          ,dv.VisitStatus
          ,fvt.ScheduledVisitId
          ,fvt.EpisodeId
          ,fvt.PatientId
          ,CONCAT_WS(' ', CONCAT (
                    p.LastName
                    ,', '
                    ,p.FirstName
                    ), p.MiddleName) AS PatientName
          ,fvt.StartOfCareDate
          ,fvt.StartOfEpisodeDate
          ,fvt.EndOfEpisodeDate
          ,fvt.isClientEpisodeVisitBillable AS Billable
          ,dv.ServiceCode
          ,DATEADD(DAY, - ((DATEPART(WEEKDAY, fvt.VisitDate) + @@DATEFIRST - 1) % 7), fvt.VisitDate) AS WeekStartDate
          ,
          --Mileage once per ScheduledVisitId (deduped)
          CASE 
               WHEN ROW_NUMBER() OVER (
                         PARTITION BY fvt.ScheduledVisitId ORDER BY fvt.ScheduledVisitId
                         ) = 1
                    THEN fvt.MileageEnd - fvt.MileageStart
               ELSE 0
               END AS Mileage
          ,DATEDIFF(MINUTE, fvt.ActualStartDateTime, fvt.ActualEndDateTime) AS ActualMinutes
          ,fvt.PayableDocumentationTimeHours
          ,fvt.PayableGrandTotalTimeHours
          ,fvt.PayableInHomeTimeHours
          ,fvt.PayableTotalTimeHours
          ,fvt.PayableTravelTimeHours
          ,fvt.CreatedDateTime
          ,fvt.ModifiedDateTime
          ,fvt.BranchCode
          ,fvt.Location
     
     FROM dbo.factVisitTimeDetails fvt
     
     LEFT JOIN dbo.dimVisit dv
          ON fvt.ScheduledVisitKey = dv.Id
               AND fvt.SourceSystem = dv.SourceSystem
     
     LEFT JOIN dbo.dimPatient p
          ON fvt.PatientId = p.PatientId
     
     WHERE fvt.SourceSystem = 'Abode'
          AND fvt.ServiceLineTypeId = 1
          AND fvt.isDeleted = 0
          AND fvt.VisitDate >= @StartDate
          AND fvt.VisitDate < @EndDate
          AND dv.WorkerId IS NOT NULL
		  --and fvt.isVisitTime = 1
     )
     ,visit_agg
AS (
     SELECT WorkerId
          ,WorkerName
          ,WeekStartDate
          ,BranchCode
          ,Location
          ,CreatedDateTime
          ,ModifiedDateTime
          ,VisitDate
          ,ScheduledVisitId
          ,VisitId
          ,VisitStatus
          ,EpisodeId
          ,PatientId
          ,PatientName
          ,StartOfCareDate
          ,StartOfEpisodeDate
          ,EndOfEpisodeDate
          ,Billable
          ,MAX(ServiceCode) AS ServiceCode
          ,SUM(ActualMinutes) AS TotalActualMinutes
          ,SUM(PayableDocumentationTimeHours) AS TotalDocumentationHours
          ,SUM(PayableGrandTotalTimeHours) AS TotalGrandTotalHours
          ,SUM(PayableInHomeTimeHours) AS TotalInHomeHours
          ,SUM(PayableTotalTimeHours) AS TotalTotalHours
          ,SUM(PayableTravelTimeHours) AS TotalTravelHours
          ,SUM(Mileage) AS TotalMileage
     
     FROM base
     
     GROUP BY WorkerId
          ,WorkerName
          ,WeekStartDate
          ,BranchCode
          ,Location
          ,VisitDate
          ,ScheduledVisitId
          ,CreatedDateTime
          ,ModifiedDateTime
          ,VisitId
          ,VisitStatus
          ,EpisodeId
          ,PatientId
          ,PatientName
          ,StartOfCareDate
          ,StartOfEpisodeDate
          ,EndOfEpisodeDate
          ,Billable
     )

SELECT v.*
     ,
     --VisitCode: first 2-digit numeric sequence
     CASE 
          WHEN PATINDEX('%[0-9][0-9]%', v.ServiceCode) > 0
               THEN SUBSTRING(v.ServiceCode, PATINDEX('%[0-9][0-9]%', v.ServiceCode), 2)
          ELSE NULL
          END AS VisitCode
     ,
     --flag to see where visit code is missing
     CASE 
          WHEN PATINDEX('%[0-9][0-9]%', v.ServiceCode) = 0
               THEN 1
          ELSE 0
          END AS IsVisitCodeMissing

FROM visit_agg v

--where v.WorkerId = 447857
--and WeekStartDate = '2025-11-23'
ORDER BY VisitDate
     ,ScheduledVisitId;
