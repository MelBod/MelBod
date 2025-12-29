DECLARE @StartDate DATE =
    DATEFROMPARTS(
        YEAR(DATEADD(MONTH, -1, GETDATE())),
        MONTH(DATEADD(MONTH, -1, GETDATE())),
        1
    );

DECLARE @EndDate DATE =
    DATEADD(DAY, 1, CAST(GETDATE() AS DATE));

WITH BaseVisits AS (
    SELECT *
    FROM dbo.factVisitTimeDetails
    WHERE SourceSystem = 'Abode'
      AND ServiceLineTypeId = 1
      AND isDeleted = 0
      AND VisitDate >= @StartDate
      AND VisitDate <  @EndDate
),
MileageByVisit AS (
    SELECT
        ScheduledVisitId,
        MAX(MileageEnd) - MIN(MileageStart) AS Mileage
    FROM BaseVisits
    WHERE MileageStart IS NOT NULL
      AND MileageEnd IS NOT NULL
    GROUP BY ScheduledVisitId
)

SELECT
    f.*,

    -- Week Start (Sunday)
    DATEADD(
        DAY,
        - ((DATEPART(WEEKDAY, f.VisitDate) + @@DATEFIRST - 1) % 7),
        f.VisitDate
    ) AS WeekStartDate,

    -- Visit-level mileage
    m.Mileage

FROM BaseVisits f
INNER JOIN MileageByVisit m
    ON f.ScheduledVisitId = m.ScheduledVisitId
WHERE m.Mileage > 0;



  SELECT
    ScheduledVisitId,
    VisitDate,
    CAST(MIN(MileageStart) AS DATE) AS MileageDate
FROM dbo.factVisitTimeDetails
WHERE MileageStart IS NOT NULL
  AND MileageEnd IS NOT NULL
GROUP BY ScheduledVisitId, VisitDate
HAVING CAST(MIN(MileageStart) AS DATE) <> VisitDate;

