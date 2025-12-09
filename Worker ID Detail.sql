DECLARE @StartDate DATE = DATEFROMPARTS(YEAR(DATEADD(MONTH, - 6, GETDATE())), MONTH(DATEADD(MONTH, - 6, GETDATE())), 1);

DECLARE @EndDate DATE = DATEADD(DAY, 1, CAST(GETDATE() AS DATE));

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
          ,dv.VisitId
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
          ,fvt.PatientVisitNumber
          ,fvt.isClientEpisodeVisitBillable
          ,dv.ServiceCode
          ,dv.VisitStatus
          ,DATEADD(day, - ((DATEPART(weekday, fvt.VisitDate) + @@DATEFIRST - 1) % 7), fvt.VisitDate) AS WeekStartDate
          ,fvt.ScheduledVisitId
          ,CASE 
               WHEN ROW_NUMBER() OVER (
                         PARTITION BY fvt.ScheduledVisitId ORDER BY fvt.ScheduledVisitId
                         ) = 1
                    THEN fvt.MileageEnd - fvt.MileageStart
               ELSE 0
               END AS Mileage
          ,DATEDIFF(MINUTE, fvt.ActualStartDateTime, fvt.ActualEndDateTime) AS ActualMinutes
          ,DATEDIFF(MINUTE, fvt.MinPayableStartDateTime, fvt.MinPayableEndDateTime) AS MinPayableMinutes
          ,fvt.PayableDocumentationTimeHours
          ,fvt.PayableGrandTotalTimeHours
          ,fvt.PayableGrandTotalTimeMins
          ,fvt.PayableInHomeTimeHours
          ,fvt.PayableTotalTimeHours
          ,fvt.PayableTravelTimeHours
          ,fvt.PayableDocumentationTimeMins
          ,fvt.PayableInHomeTimeMins
          ,fvt.PayableTotalTimeMins
          ,fvt.PayableTravelTimeMins
          ,fvt.CreatedDateTime
          ,fvt.ModifiedDateTime
          ,fvt.BranchCode
          ,fvt.Location
     
     FROM dbo.factVisitTimeDetails fvt
     
     LEFT JOIN dbo.dimVisit dv WITH (NOLOCK)
          ON fvt.ScheduledVisitKey = dv.Id
               AND fvt.SourceSystem = dv.SourceSystem
     
     LEFT JOIN dbo.dimPatient p
          ON fvt.PatientId = p.PatientId
     
     WHERE fvt.SourceSystem = 'Abode'
          AND fvt.ServiceLineTypeId = 1
          AND fvt.isDeleted = 0
          AND fvt.VisitDate >= @StartDate
          AND fvt.VisitDate < @EndDate
     )

SELECT WorkerId
     ,WorkerNameFirst
     ,WorkerNameLast
     ,WorkerName
     ,WeekStartDate
     ,BranchCode
     ,Location
     ,ISNULL(ActualMinutes, 0) AS TotalActualMinutes
     ,ISNULL(Mileage, 0) AS TotalMileage
     ,ISNULL(MinPayableMinutes, 0) AS TotalMinPayableMinutes
     ,ISNULL(PayableDocumentationTimeMins, 0) AS TotalDocumentationMinutes
     ,ISNULL(PayableInHomeTimeMins, 0) AS TotalInHomeMinutes
     ,ISNULL(PayableTotalTimeMins, 0) AS TotalPayableMinutes
     ,ISNULL(PayableTravelTimeMins, 0) AS TotalTravelMinutes
     ,ISNULL(PayableDocumentationTimeHours, 0) AS TotalDocumentationHours
     ,ISNULL(PayableGrandTotalTimeHours, 0) AS TotalGrandTotalHours
     ,ISNULL(PayableGrandTotalTimeMins, 0) AS TotalGrandTotalMins
     ,ISNULL(PayableInHomeTimeHours, 0) AS TotalInHomeHours
     ,ISNULL(PayableTotalTimeHours, 0) AS TotalTotalHours
     ,ISNULL(PayableTravelTimeHours, 0) AS TotalTravelHours
     ,VisitDate
     ,VisitId
     ,ScheduledVisitId
     ,EpisodeId
     ,PatientId
     ,PatientName
     ,ServiceCode
     ,VisitStatus
     ,isClientEpisodeVisitBillable AS Billable
     ,CreatedDateTime
     ,ModifiedDateTime
     ,StartOfCareDate
     ,StartOfEpisodeDate
     ,EndOfEpisodeDate
     ,PatientVisitNumber

FROM base

WHERE WorkerId IS NOT NULL

ORDER BY VisitDate
     ,ScheduledVisitId;
