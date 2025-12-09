-- Base Episodes CTE (13 months back, Service Line = 1)
WITH CTE_Episodes AS (
    SELECT 
        e.EpiId,
        e.EpiStatus,
        e.EpiPaId,
        e.EpiBranchcode,
        e.EpiStartOfEpisode,
        e.EpiEndOfEpisode,
        e.EpiSOCDate,
        e.CreatedDateTime,
        e.ModifiedDateTime
    FROM dbo.ClientEpisodesAll e
    WHERE e.EpiSlId = 1
      AND e.EpiStartOfEpisode >= DATEADD(MONTH, -13, CAST(GETDATE() AS DATE))
),

-- Insurance details from EpisodeFS
CTE_EpisodeInsurance AS (
    SELECT 
        e.EpiId,
        e.EpiPaId,
        e.EpiBranchcode,
        e.EpiStatus,
        e.EpiStartOfEpisode,
        e.EpiEndOfEpisode,
        e.EpiSOCDate,
        cefs.CefsId,
        cefs.CefsPsId AS InsuranceId,
        i.InsuranceTypeId,
        i.InsuranceType
    FROM CTE_Episodes e
    INNER JOIN dbo.ClientEpisodeFs cefs
        ON e.EpiId = cefs.CefsEpiId
    LEFT JOIN dbo.dimInsurance i
        ON cefs.CefsPsId = i.InsuranceId
),

-- Patient details (with concatenated name)
CTE_EpisodePatient AS (
    SELECT 
        ei.EpiId,
        ei.EpiBranchcode,
        ei.EpiStatus,
        ei.EpiStartOfEpisode,
        ei.EpiEndOfEpisode,
        ei.EpiSOCDate,
        ei.CefsId,
        ei.InsuranceId,
        ei.InsuranceTypeId,
        ei.InsuranceType,
        p.PatientId,
        CONCAT(p.LastName, ', ', p.FirstName) AS PatientName
    FROM CTE_EpisodeInsurance ei
    LEFT JOIN dbo.dimPatient p
        ON ei.EpiPaId = p.PatientId
)

-- Final test output
SELECT *
FROM CTE_EpisodePatient;
