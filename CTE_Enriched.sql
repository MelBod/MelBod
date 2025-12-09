-- Parameters
DECLARE @SourceSystem SYSNAME = 'Abode';
DECLARE @StartDate DATE = DATEADD(MONTH, -13, CAST(GETDATE() AS DATE));
DECLARE @EndDate DATE   = CAST(GETDATE() AS DATE);

;WITH CTE_Episodes AS (
    SELECT
        cea.EpiId,
        cea.EpiStatus,
        cea.EpiStartOfEpisode,
        cea.EpiEndOfEpisode,
        cea.EpiSOCDate,
        cea.EpiBranchcode,
        cea.EpiPaId   -- Patient Id
    FROM dbo.ClientEpisodesAll cea
    WHERE cea.SourceSystem = @SourceSystem
      AND cea.EpiSlId = 1   -- Always service line 1
      AND cea.EpiStartOfEpisode >= @StartDate
      AND cea.EpiStartOfEpisode <= @EndDate
),
CTE_Schedule AS (
    SELECT
        csv.CsvId,
        csv.CsvEpiId,
        csv.CsvSchedDate,
        csv.CsvStatus,
        csv.CsvScId,
        csv.CsvVmId
    FROM dbo.ClientSchedVisits csv
    INNER JOIN CTE_Episodes e
        ON csv.CsvEpiId = e.EpiId
    WHERE csv.SourceSystem = @SourceSystem
      AND csv.CsvSchedDate BETWEEN @StartDate AND @EndDate
),
CTE_Enriched AS (
    SELECT
        s.CsvId,
        s.CsvEpiId,
        s.CsvSchedDate,
        s.CsvStatus,
        s.CsvScId,
        s.CsvVmId,
        e.EpiStatus,
        e.EpiStartOfEpisode,
        e.EpiEndOfEpisode,
        e.EpiSOCDate,
        e.EpiBranchcode,
        p.PatientId,   -- unified patient id
        sc.ScCode,
        sc.ScDesc,
        sc.ScBillable,
        sc.ScPayable,
        sc.ScDiscipline,
        vs.VsDescription,
        vmr.VmDesc AS VisitMissedReason
    FROM CTE_Schedule s
    INNER JOIN CTE_Episodes e
        ON s.CsvEpiId = e.EpiId
    LEFT JOIN dbo.ServiceCodes sc
        ON s.CsvScId = sc.ScId
    LEFT JOIN dbo.VisitStatuses vs
        ON s.CsvStatus = vs.VsStatus
    LEFT JOIN dbo.VisitMissedReasons vmr
        ON s.CsvVmId = vmr.VmId
    LEFT JOIN dbo.dimPatient p
        ON e.EpiPaId = p.PatientId
)
SELECT TOP 100 *
FROM CTE_Enriched;
