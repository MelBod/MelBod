DECLARE @StartDate DATE =
    DATEFROMPARTS(
        YEAR(DATEADD(MONTH, -6, GETDATE())),
        MONTH(DATEADD(MONTH, -6, GETDATE())),
        1
    );

DECLARE @EndDate DATE =
    DATEADD(DAY, 1, CAST(GETDATE() AS DATE));

WITH mileage_base AS (
    SELECT
        DATEADD(
            DAY,
            - ((DATEPART(WEEKDAY, fvt.VisitDate) + @@DATEFIRST - 1) % 7),
            fvt.VisitDate
        ) AS WeekStartDate,

        fvt.VisitDate,
        dv.WorkerId,
        dv.WorkerNameLast,
        CONCAT(dv.WorkerNameLast, ', ', dv.WorkerNameFirst) AS WorkerName,
        dv.ServiceCode,

        /* classify mileage */
        CASE
            WHEN fvt.isVisitTime = 1 THEN 'Visit'
            ELSE 'NonVisit'
        END AS MileageType,

        (fvt.MileageEnd - fvt.MileageStart) AS Mileage
    FROM dbo.factVisitTimeDetails fvt
    INNER JOIN dbo.dimVisit dv
        ON fvt.ScheduledVisitKey = dv.Id
       AND fvt.SourceSystem = dv.SourceSystem
       AND dv.WorkerId IS NOT NULL
    WHERE fvt.SourceSystem = 'Abode'
      AND fvt.ServiceLineTypeId = 1
      AND fvt.isDeleted = 0
      AND fvt.VisitDate >= @StartDate
      AND fvt.VisitDate <  @EndDate
      AND fvt.MileageStart IS NOT NULL
      AND fvt.MileageEnd IS NOT NULL
),

pivoted AS (
    SELECT
        WeekStartDate,
        VisitDate,
        WorkerId,
        WorkerNameLast,
        WorkerName,

        SUM(CASE WHEN MileageType = 'Visit'    THEN Mileage ELSE 0 END) AS VisitMileage,
        SUM(CASE WHEN MileageType = 'NonVisit' THEN Mileage ELSE 0 END) AS NonVisitMileage
    FROM mileage_base
    GROUP BY
        WeekStartDate,
        VisitDate,
        WorkerId,
        WorkerNameLast,
        WorkerName
)

SELECT *
FROM pivoted
WHERE WorkerNameLast = 'BURNSIDE'
  AND WeekStartDate = '2025-11-23'
ORDER BY
    VisitDate;
