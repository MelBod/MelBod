DECLARE @StartDate DATE     = DATEADD(MONTH, -13, CAST(GETDATE() AS DATE)); -- rolling 13 months
DECLARE @EndDate   DATE     = DATEADD(DAY, 60, CAST(GETDATE() AS DATE));
DECLARE @ServiceLineId INT  = 1;
DECLARE @SourceSystem SYSNAME = 'Abode';

;WITH CTE_Episodes AS (
    SELECT TOP 100
        e.EpiId,
        e.EpiPaId      AS PatientId,
        e.EpiBranchcode,
        e.EpiStatus,
        CAST(e.EpiStartOfEpisode AS DATE) AS EpiStartOfEpisode,
        CAST(e.EpiEndOfEpisode   AS DATE) AS EpiEndOfEpisode,
        CAST(e.EpiSOCDate        AS DATE) AS EpiSOCDate,
        e.SourceSystem
    FROM dbo.ClientEpisodesAll e
    WHERE e.EpiSlId = @ServiceLineId
      AND e.SourceSystem = @SourceSystem
      AND e.EpiStartOfEpisode >= @StartDate
),
CTE_EpisodeFs AS (
    SELECT *
    FROM (
        SELECT
            cefs.CefsEpiId AS EpiId,
            cefs.CefsId,
            cefs.CefsPsId AS InsuranceId,
            cefs.CefsActive,
            ROW_NUMBER() OVER (
                PARTITION BY cefs.CefsEpiId
                ORDER BY cefs.ModifiedDateTime DESC, cefs.CefsId DESC
            ) AS rn
        FROM dbo.ClientEpisodeFs cefs
        INNER JOIN CTE_Episodes e
            ON e.EpiId = cefs.CefsEpiId
           AND e.SourceSystem = cefs.SourceSystem
        WHERE cefs.CefsActive = 'Y'
    ) t
    WHERE rn = 1   -- only keep the latest FS row per EpiId
)
-- Verify no duplicates remain
SELECT 
    EpiId,
    COUNT(*) AS FsCount
FROM CTE_EpisodeFs
GROUP BY EpiId
ORDER BY FsCount DESC, EpiId;




SELECT
    cefs.CefsEpiId AS EpiId,
    cefs.CefsId,
    cefs.CefsPsId AS InsuranceId,
    cefs.CefsActive,
    cefs.CreatedDateTime,
    cefs.ModifiedDateTime
FROM dbo.ClientEpisodeFs cefs
WHERE cefs.CefsEpiId = 820107
  AND cefs.CefsActive = 'Y'
ORDER BY cefs.ModifiedDateTime DESC, cefs.CefsId DESC;

