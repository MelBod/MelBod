WITH base AS (
    SELECT 
          dv.WorkerId
        , CONCAT(dv.WorkerNameLast, ', ', dv.WorkerNameFirst) AS WorkerName

        , fvt.VisitDate
        , DATEADD(day, -DATEPART(weekday, fvt.VisitDate) + 1, fvt.VisitDate) AS WeekStartDate

        , fvt.EpisodeId
        , fvt.PatientId
        , fvt.ScheduledVisitId

        -- Derived fields
        , DATEDIFF(MINUTE, fvt.ActualStartDateTime, fvt.ActualEndDateTime) AS ActualMinutes
        , fvt.MileageEnd - fvt.MileageStart AS Mileage

        -- Payable Minutes
        , fvt.PayableDocumentationTimeMins
        , fvt.PayableInHomeTimeMins
        , fvt.PayableTotalTimeMins
        , fvt.PayableTravelTimeMins

        -- Payable Hours
        , fvt.PayableDocumentationTimeHours
        , fvt.PayableGrandTotalTimeHours
        , fvt.PayableGrandTotalTimeMins
        , fvt.PayableInHomeTimeHours
        , fvt.PayableTotalTimeHours
        , fvt.PayableTravelTimeHours

    FROM dbo.factVisitTimeDetails fvt
    INNER JOIN dbo.dimVisit dv WITH (NOLOCK)
        ON fvt.ScheduledVisitKey = dv.Id
       AND fvt.SourceSystem = dv.SourceSystem
    WHERE fvt.SourceSystem = 'Abode'
      AND fvt.ServiceLineTypeId = 1
      AND fvt.isDeleted = 0
      AND fvt.VisitDate >= DATEFROMPARTS(
            YEAR(DATEADD(MONTH, -13, GETDATE())),
            MONTH(DATEADD(MONTH, -13, GETDATE())),
            1
        )
      AND fvt.VisitDate < DATEADD(DAY, 1, CAST(GETDATE() AS DATE))
)

SELECT 
      WorkerId
    , WorkerName
    , WeekStartDate

    , COUNT(DISTINCT PatientId) AS DistinctPatients
    , COUNT(DISTINCT EpisodeId) AS DistinctEpisodes
    , COUNT(DISTINCT ScheduledVisitId) AS DistinctVisits

    , SUM(ActualMinutes) AS TotalActualMinutes
    , SUM(Mileage) AS TotalMileage

    , SUM(PayableDocumentationTimeMins) AS TotalDocumentationMinutes
    , SUM(PayableInHomeTimeMins) AS TotalInHomeMinutes
    , SUM(PayableTotalTimeMins) AS TotalPayableMinutes
    , SUM(PayableTravelTimeMins) AS TotalTravelMinutes

    , SUM(PayableDocumentationTimeHours) AS TotalDocumentationHours
    , SUM(PayableGrandTotalTimeHours) AS TotalGrandTotalHours
    , SUM(PayableGrandTotalTimeMins) AS TotalGrandTotalMins
    , SUM(PayableInHomeTimeHours) AS TotalInHomeHours
    , SUM(PayableTotalTimeHours) AS TotalTotalHours
    , SUM(PayableTravelTimeHours) AS TotalTravelHours

FROM base
GROUP BY 
      WorkerId
    , WorkerName
    , WeekStartDate
ORDER BY 
      WorkerId
    , WeekStartDate;
