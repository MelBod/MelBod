SELECT
    TimeSlipCategoryId,
    TimeSlipCategoryKey,
    isVisitTime,
    isNonVisitTime,
    COUNT(*) AS [RowCount],
    SUM(MileageEnd - MileageStart) AS TotalMileage
FROM dbo.factVisitTimeDetails
WHERE MileageStart IS NOT NULL
  AND MileageEnd IS NOT NULL
GROUP BY
    TimeSlipCategoryId,
    TimeSlipCategoryKey,
    isVisitTime,
    isNonVisitTime
ORDER BY TotalMileage DESC;


SELECT TOP 1000
    ScheduledVisitId,
    VisitDate,
    CreatedDateTime,
    ModifiedDateTime,
    MileageStart,
    MileageEnd,
    (MileageEnd - MileageStart) AS Mileage,
    isVisitTime,
    isNonVisitTime,
    TimeSlipCategoryId,
    TimeSlipCategoryKey
FROM dbo.factVisitTimeDetails
WHERE MileageStart IS NOT NULL
  AND MileageEnd IS NOT NULL
  AND TimeSlipCategoryId IS NULL
ORDER BY CreatedDateTime DESC;

/*_____________________________________________________________________________________________*/

DECLARE @StartDate DATE =
    DATEFROMPARTS(
        YEAR(DATEADD(MONTH, -6, GETDATE())),
        MONTH(DATEADD(MONTH, -6, GETDATE())),
        1
    );

DECLARE @EndDate DATE =
    DATEADD(DAY, 1, CAST(GETDATE() AS DATE));

SELECT
    DATEADD(
        DAY,
        - ((DATEPART(WEEKDAY, fvt.VisitDate) + @@DATEFIRST - 1) % 7),
        fvt.VisitDate
    ) AS WeekStartDate,
    fvt.VisitDate,
    CONCAT(dv.WorkerNameLast, ', ', dv.WorkerNameFirst) AS WorkerName,
    dv.WorkerId,
    CONCAT_WS(
        ' ',
        CONCAT(p.LastName, ', ', p.FirstName),
        p.MiddleName
    ) AS PatientName,
    dv.ServiceCode,
    fvt.MileageStart,
    fvt.MileageEnd,
    (fvt.MileageEnd - fvt.MileageStart) AS NonVisitMiles,
    fvt.isVisitTime,
    fvt.isNonVisitTime,
    fvt.TimeSlipCategoryId,
    fvt.TimeSlipCategoryKey,
    fvt.CreatedDateTime,
    fvt.ModifiedDateTime

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

ORDER BY
    WeekStartDate,
    WorkerName,
    fvt.VisitDate,
    fvt.CreatedDateTime;


