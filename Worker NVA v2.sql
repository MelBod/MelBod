DECLARE @StartDate DATE =
    DATEFROMPARTS(
        YEAR(DATEADD(MONTH, -6, GETDATE())),
        MONTH(DATEADD(MONTH, -6, GETDATE())),
        1
    );

DECLARE @EndDate DATE =
    DATEADD(DAY, 1, CAST(GETDATE() AS DATE));

SELECT
    /* Visit identity */
    fvt.ScheduledVisitId,
    fvt.ScheduledVisitKey,
    fvt.VisitDate,

    DATEADD(
        DAY,
        - ((DATEPART(WEEKDAY, fvt.VisitDate) + @@DATEFIRST - 1) % 7),
        fvt.VisitDate
    ) AS WeekStartDate,

    /* Visit attributes (dimVisit) */
    dv.VisitId,
    dv.VisitStatus,
    dv.ServiceCode,

    /* VisitCode (derived from ServiceCode) */
    CASE
        WHEN PATINDEX('%[0-9][0-9]%', dv.ServiceCode) > 0
            THEN SUBSTRING(
                    dv.ServiceCode,
                    PATINDEX('%[0-9][0-9]%', dv.ServiceCode),
                    2
                 )
        ELSE NULL
    END AS VisitCode,

    dv.WorkerId,
    CONCAT(dv.WorkerNameLast, ', ', dv.WorkerNameFirst) AS WorkerName,

    /* Patient */
    fvt.PatientId,
    CONCAT_WS(
        ' ',
        CONCAT(p.LastName, ', ', p.FirstName),
        p.MiddleName
    ) AS PatientName,

    /* Episode */
    fvt.EpisodeId,
    fvt.StartOfCareDate,
    fvt.StartOfEpisodeDate,
    fvt.EndOfEpisodeDate,
    fvt.isClientEpisodeVisitBillable AS Billable,

    /* Time / duration (row-level) */
    fvt.ActualStartDateTime,
    fvt.ActualEndDateTime,
    DATEDIFF(
        MINUTE,
        fvt.ActualStartDateTime,
        fvt.ActualEndDateTime
    ) AS ActualMinutes,

    fvt.PayableDocumentationTimeHours,
    fvt.PayableGrandTotalTimeHours,
    fvt.PayableInHomeTimeHours,
    fvt.PayableTotalTimeHours,
    fvt.PayableTravelTimeHours,

 
    fvt.MileageStart,
    fvt.MileageEnd,
    fvt.ServiceTripFee,
    fvt.isMileagePayable,
    fvt.isMileageProcessed,

  
    fvt.CreatedDateTime,
    fvt.ModifiedDateTime,

  
    fvt.isVisitTime,
    fvt.isNonVisitTime,
    fvt.isTimeSlipPayable,
    fvt.isStopEventCompleted,
    fvt.isStopEventIncomplete,
    fvt.isServiceActive,

    /* Org / slicing */
    fvt.BranchCode,
    fvt.Location

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

ORDER BY
    fvt.VisitDate,
    fvt.ScheduledVisitId,
    fvt.CreatedDateTime;
