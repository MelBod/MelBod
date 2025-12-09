-- Parameters
DECLARE @SourceSystem SYSNAME = 'Abode';
DECLARE @ServiceLineId INT = 1;
DECLARE @StartDate DATE = DATEADD(MONTH, -13, CAST(GETDATE() AS DATE));
DECLARE @EndDate DATE   = CAST(GETDATE() AS DATE);

;WITH CTE_Episodes AS (
    SELECT
        cea.EpiId,
        cea.EpiSlId,
        cea.EpiStatus,
        cea.EpiStartOfEpisode,
        cea.EpiEndOfEpisode,
        cea.EpiSOCDate,
        cea.EpiBranchcode,
        cea.EpiPaId
    FROM dbo.ClientEpisodesAll cea
    WHERE cea.SourceSystem = @SourceSystem
      AND cea.EpiSlId = @ServiceLineId
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
)
SELECT TOP 100 *
FROM CTE_Schedule;
