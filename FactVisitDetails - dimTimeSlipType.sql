DECLARE @StartDate DATE = DATEFROMPARTS(YEAR(DATEADD(MONTH, - 6, GETDATE())), MONTH(DATEADD(MONTH, - 6, GETDATE())), 1);

DECLARE @EndDate DATE = DATEADD(DAY, 1, CAST(GETDATE() AS DATE));

WITH miles
AS (
     SELECT dv.WorkerId
          ,CONCAT (
               dv.WorkerNameLast
               ,', '
               ,dv.WorkerNameFirst
               ) AS WorkerName
          ,fvt.VisitDate
          ,DATEADD(DAY, - ((DATEPART(WEEKDAY, fvt.VisitDate) + @@DATEFIRST - 1) % 7), fvt.VisitDate) AS WeekStartDate
          ,dv.VisitId
          ,dv.VisitStatus
          ,fvt.ScheduledVisitId
          ,dv.ServiceCode
          ,fvt.BranchCode
          ,fvt.Location
          ,(fvt.MileageEnd - fvt.MileageStart) AS Miles
          ,tst.TimeSlipTypeId
     
     FROM dbo.factVisitTimeDetails fvt
     
     INNER JOIN dbo.dimVisit dv
          ON fvt.ScheduledVisitKey = dv.Id
               AND fvt.SourceSystem = dv.SourceSystem
     
     LEFT JOIN dbo.dimTimeSlipType tst
          ON fvt.TimeSlipTypeId = tst.Id
     
     WHERE fvt.SourceSystem = 'Abode'
          AND fvt.ServiceLineTypeId = 1
          AND fvt.isDeleted = 0
          AND fvt.MileageStart IS NOT NULL
          AND fvt.MileageEnd IS NOT NULL
          AND fvt.VisitDate >= @StartDate
          AND fvt.VisitDate < @EndDate
     )

SELECT WorkerId
     ,WorkerName
     ,WeekStartDate
     ,BranchCode
     ,Location
     ,SUM(CASE 
               WHEN TimeSlipTypeId = 4
                    THEN Miles
               ELSE 0
               END) AS NonVisitMileage
     ,SUM(CASE 
               WHEN TimeSlipTypeId <> 4
                    THEN Miles
               ELSE 0
               END) AS VisitMileage
     ,SUM(Miles) AS TotalMileage

FROM miles

GROUP BY WorkerId
     ,WorkerName
     ,WeekStartDate
     ,BranchCode
     ,Location

ORDER BY WeekStartDate
     ,WorkerName;
