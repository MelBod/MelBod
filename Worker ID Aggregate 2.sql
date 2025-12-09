WITH base
AS (
     SELECT dv.WorkerId
          ,dv.WorkerNameFirst
          ,dv.WorkerNameLast
          ,CONCAT (
               dv.WorkerNameLast
               ,', '
               ,dv.WorkerNameFirst
               ) AS WorkerName
          ,fvt.VisitDate
		  --Sunday week start
          ,DATEADD(day, - DATEPART(weekday, fvt.VisitDate) + 1, fvt.VisitDate) AS WeekStartDate
		  ,DATEADD(day, -((DATEPART(weekday, fvt.VisitDate) + @@DATEFIRST - 1) % 7), fvt.VisitDate) as WeekStartDate2
		  --Monday week start
		  --DATEADD(day, -((DATEPART(weekday, fvt.VisitDate) + @@DATEFIRST - 2) % 7), fvt.VisitDate) AS WeekStartDateMonday

          ,fvt.EpisodeId
          ,fvt.PatientId
          ,fvt.ScheduledVisitId
          -- Derived fields
          ,DATEDIFF(MINUTE, fvt.ActualStartDateTime, fvt.ActualEndDateTime) AS ActualMinutes
          ,fvt.MileageEnd - fvt.MileageStart AS Mileage
          ,DATEDIFF(MINUTE, fvt.MinPayableStartDateTime, fvt.MinPayableEndDateTime) AS MinPayableMinutes
          -- Payable Minutes
          ,fvt.PayableDocumentationTimeMins
          ,fvt.PayableInHomeTimeMins
          ,fvt.PayableTotalTimeMins
          ,fvt.PayableTravelTimeMins
          -- Payable Hours / Mins
          ,fvt.PayableDocumentationTimeHours
          ,fvt.PayableGrandTotalTimeHours
          ,fvt.PayableGrandTotalTimeMins
          ,fvt.PayableInHomeTimeHours
          ,fvt.PayableTotalTimeHours
          ,fvt.PayableTravelTimeHours
          ,fvt.BranchCode
          ,fvt.LocationHierarchyKey
          ,fvt.Location
     
     FROM dbo.factVisitTimeDetails fvt
     
     LEFT JOIN dbo.dimVisit dv WITH (NOLOCK)
          ON fvt.ScheduledVisitKey = dv.Id
               AND fvt.SourceSystem = dv.SourceSystem
     
     WHERE fvt.SourceSystem = 'Abode'
          AND fvt.ServiceLineTypeId = 1
          AND fvt.isDeleted = 0
          AND fvt.VisitDate >= DATEFROMPARTS(YEAR(DATEADD(MONTH, - 13, GETDATE())), MONTH(DATEADD(MONTH, - 13, GETDATE())), 1)
          AND fvt.VisitDate < DATEADD(DAY, 1, CAST(GETDATE() AS DATE))
     )

SELECT WorkerId
     ,WorkerNameFirst
     ,WorkerNameLast
     ,WorkerName
     ,WeekStartDate
     ,BranchCode
     ,LocationHierarchyKey
     ,Location
     ,COUNT(DISTINCT PatientId) AS DistinctPatients
     ,COUNT(DISTINCT EpisodeId) AS DistinctEpisodes
     ,COUNT(DISTINCT ScheduledVisitId) AS DistinctVisits
     ,SUM(ActualMinutes) AS TotalActualMinutes
     ,SUM(Mileage) AS TotalMileage
     ,SUM(MinPayableMinutes) AS TotalMinPayableMinutes
     ,SUM(PayableDocumentationTimeMins) AS TotalDocumentationMinutes
     ,SUM(PayableInHomeTimeMins) AS TotalInHomeMinutes
     ,SUM(PayableTotalTimeMins) AS TotalPayableMinutes
     ,SUM(PayableTravelTimeMins) AS TotalTravelMinutes
     ,SUM(PayableDocumentationTimeHours) AS TotalDocumentationHours
     ,SUM(PayableGrandTotalTimeHours) AS TotalGrandTotalHours
     ,SUM(PayableGrandTotalTimeMins) AS TotalGrandTotalMins
     ,SUM(PayableInHomeTimeHours) AS TotalInHomeHours
     ,SUM(PayableTotalTimeHours) AS TotalTotalHours
     ,SUM(PayableTravelTimeHours) AS TotalTravelHours
     ,CASE 
          WHEN SUM(Mileage) < 300
               THEN 0
          ELSE 1 + FLOOR((SUM(Mileage) - 300) / 75.0)
          END AS MileagePoints

FROM base

WHERE WorkerId IS NOT NULL --AND WorkerId = 406545 and WeekStartDate = '2025-11-16'

GROUP BY WorkerId
     ,WorkerNameFirst
     ,WorkerNameLast
     ,WorkerName
     ,WeekStartDate
     ,BranchCode
     ,LocationHierarchyKey
     ,Location

ORDER BY WorkerId
     ,WeekStartDate;
