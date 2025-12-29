DECLARE @WorkerLastName  VARCHAR(100) = 'BURNSIDE';
DECLARE @WeekStartDate   DATE = '2025-11-23';

WITH mileage_rows AS (
    SELECT
        fvt.ScheduledVisitId,
        fvt.VisitDate,
        DATEADD(
            DAY,
            - ((DATEPART(WEEKDAY, fvt.VisitDate) + @@DATEFIRST - 1) % 7),
            fvt.VisitDate
        ) AS WeekStartDate,

        dv.WorkerId,
        dv.WorkerNameLast,
        CONCAT(dv.WorkerNameLast, ', ', dv.WorkerNameFirst) AS WorkerName,

        dv.ServiceCode,

        fvt.PatientId,
        CONCAT_WS(' ', CONCAT(p.LastName, ', ', p.FirstName), p.MiddleName) AS PatientName,

        fvt.MileageStart,
        fvt.MileageEnd,
        (fvt.MileageEnd - fvt.MileageStart) AS Miles,

        fvt.isVisitTime,
        fvt.isNonVisitTime,
        fvt.TimeSlipCategoryId,
        fvt.TimeSlipCategoryKey,

        fvt.CreatedDateTime,
        fvt.ModifiedDateTime,

        /* De-dupe: same mileage segment can appear on multiple rows */
        ROW_NUMBER() OVER (
            PARTITION BY
                fvt.ScheduledVisitId,
                fvt.MileageStart,
                fvt.MileageEnd,
                CAST(fvt.CreatedDateTime AS DATETIME2(0))
            ORDER BY fvt.ModifiedDateTime DESC, fvt.CreatedDateTime DESC
        ) AS rn
    FROM dbo.factVisitTimeDetails fvt
    INNER JOIN dbo.dimVisit dv
        ON fvt.ScheduledVisitKey = dv.Id
       AND fvt.SourceSystem = dv.SourceSystem
    LEFT JOIN dbo.dimPatient p
        ON fvt.PatientId = p.PatientId
    WHERE fvt.SourceSystem = 'Abode'
      AND fvt.ServiceLineTypeId = 1
      AND fvt.isDeleted = 0
      AND fvt.MileageStart IS NOT NULL
      AND fvt.MileageEnd IS NOT NULL
),
mileage_dedup AS (
    SELECT *
    FROM mileage_rows
    WHERE rn = 1
      AND WorkerNameLast = @WorkerLastName
      AND WeekStartDate = @WeekStartDate
),
classified AS (
    SELECT
        WeekStartDate,
        WorkerId,
        WorkerName,

        /* Visit miles = mileage rows flagged visit time */
        SUM(CASE WHEN isVisitTime = 1 THEN Miles ELSE 0 END) AS VisitMiles,

        /* Non-visit miles = not visit time AND either explicit non-visit or uncategorized */
        SUM(CASE
                WHEN isVisitTime = 0
                 AND (isNonVisitTime = 1 OR TimeSlipCategoryId IS NULL)
                    THEN Miles
                ELSE 0
            END) AS NonVisitMiles,

        SUM(Miles) AS TotalMiles_AllDedupRows
    FROM mileage_dedup
    GROUP BY
        WeekStartDate,
        WorkerId,
        WorkerName
)
SELECT *
FROM classified
WHERE WorkerName = 'BURNSIDE, WENDY'
  AND WeekStartDate = '2025-11-23';
