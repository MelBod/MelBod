DECLARE @StartDate DATE =
    DATEFROMPARTS(
        YEAR(DATEADD(MONTH, -6, GETDATE())),
        MONTH(DATEADD(MONTH, -6, GETDATE())),
        1
    );

DECLARE @EndDate DATE =
    DATEADD(DAY, 1, CAST(GETDATE() AS DATE));

WITH non_visit_mileage AS (
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

        fvt.PatientId,
        CONCAT_WS(
            ' ',
            CONCAT(p.LastName, ', ', p.FirstName),
            p.MiddleName
        ) AS PatientName,

        dv.ServiceCode,

        /* Non-visit mileage */
        SUM(fvt.MileageEnd - fvt.MileageStart) AS NonVisitMiles

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
      AND fvt.VisitDate <  @EndDate
      AND fvt.MileageStart IS NOT NULL
      AND fvt.MileageEnd IS NOT NULL
      AND fvt.isVisitTime = 0
      AND (
            fvt.isNonVisitTime = 1
            OR fvt.TimeSlipCategoryId IS NULL
          )
      AND dv.WorkerNameLast = 'BURNSIDE'
      AND DATEADD(
            DAY,
            - ((DATEPART(WEEKDAY, fvt.VisitDate) + @@DATEFIRST - 1) % 7),
            fvt.VisitDate
          ) = '2025-11-23'

    GROUP BY
        DATEADD(
            DAY,
            - ((DATEPART(WEEKDAY, fvt.VisitDate) + @@DATEFIRST - 1) % 7),
            fvt.VisitDate
        ),
        fvt.VisitDate,
        dv.WorkerId,
        dv.WorkerNameLast,
        dv.WorkerNameFirst,
        fvt.PatientId,
        p.LastName,
        p.FirstName,
        p.MiddleName,
        dv.ServiceCode
)

SELECT *
FROM non_visit_mileage
WHERE WorkerNameLast = 'BURNSIDE'
  AND WeekStartDate = '2025-11-23' 
ORDER BY
    WorkerName,
    VisitDate,
    PatientName,
    ServiceCode;
