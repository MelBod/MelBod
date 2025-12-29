SELECT
    FORMAT(csv.CsvSchedDate, 'yyyy-MM') AS YearMonth,
	
    CASE 
        WHEN CEA.EpiEndOfEpisode <= CAST(GETDATE() - 1 AS DATE)
            THEN 'Closed'
        ELSE 'Open'
    END AS OpenClosedFlag,

    SUM(
        CASE 
            WHEN vs.VsDescription = 'MISSED'
                 AND sc.ScBillable = 'Y'
                 AND sc.ScCode NOT LIKE '%66%'
                 AND csv.CsvSchedDate >= cea.EpiStartOfEpisode
                 AND csv.CsvSchedDate <= ISNULL(cea.EpiEndOfEpisode, '9999-12-31')
            THEN 1 
            ELSE 0 
        END
    ) AS MissedVisits,

    SUM(
        CASE 
            WHEN vs.VsDescription = 'COMPLETED'
                 AND sc.ScCode NOT LIKE '%66%'
                 AND cev.CevBillable = 1
            THEN 1 
            ELSE 0 
        END
    ) AS CompletedVisits,

    SUM(
        CASE 
            WHEN vs.VsDescription = 'MISSED'
                 AND sc.ScBillable = 'Y'
                 AND sc.ScCode NOT LIKE '%66%' 
            THEN 1
            WHEN vs.VsDescription = 'COMPLETED'
                 AND sc.ScCode NOT LIKE '%66%'
                 AND cev.CevBillable = 1
            THEN 1
            ELSE 0
        END
    ) AS [Completed + Missed]

FROM dbo.ClientSchedVisits csv WITH (NOLOCK)
     
INNER JOIN dbo.VisitStatuses vs WITH (NOLOCK)
    ON csv.CsvStatus = vs.VsStatus
   AND csv.SourceSystem = vs.SourceSystem

INNER JOIN dbo.ServiceCodes sc WITH (NOLOCK)
    ON csv.CsvScId = sc.ScId
   AND csv.SourceSystem = sc.SourceSystem

INNER JOIN dbo.Disciplines d WITH (NOLOCK)
    ON sc.ScDiscipline = d.DscCode
   AND sc.SourceSystem = d.SourceSystem

INNER JOIN dbo.ClientEpisodesAll cea WITH (NOLOCK)
    ON csv.CsvEpiId = cea.EpiId
   AND csv.SourceSystem = cea.SourceSystem

INNER JOIN dbo.dimBranch b WITH (NOLOCK)
    ON cea.EpiBranchcode = b.BranchCode
   AND cea.SourceSystem = b.SourceSystem

INNER JOIN dbo.dimPatient p WITH (NOLOCK)
    ON cea.EpiPaId = p.PatientId
   AND cea.SourceSystem = p.SourceSystem

LEFT JOIN dbo.ClientEpisodeVisitsAll cev WITH (NOLOCK)
    ON csv.CsvId = cev.CevCsvId
   AND csv.SourceSystem = cev.SourceSystem
   AND cev.CevDeleted = 0

LEFT JOIN dbo.ClientEpisodeFs cefs WITH (NOLOCK)
    ON cea.EpiId = cefs.CefsEpiId
   AND cefs.CefsPs = 'P'
   AND cefs.CefsActive = 'Y'
   AND cea.SourceSystem = cefs.SourceSystem

LEFT JOIN dbo.VisitMissedReasons vmr WITH (NOLOCK)
    ON csv.CsvVmId = vmr.VmId
   AND csv.SourceSystem = vmr.SourceSystem

LEFT JOIN dimInsurance i WITH (NOLOCK)
    ON cefs.CefsPsid = i.InsuranceId
   AND cefs.SourceSystem = i.SourceSystem

LEFT JOIN dbo.dimWorker dw WITH (NOLOCK)
    ON cev.CevAgId = dw.WorkerId
   AND cev.SourceSystem = dw.SourceSystem

WHERE  
    csv.CsvSchedDate BETWEEN 
        DATEADD(MONTH, -12, DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0))
        AND DATEADD(DAY, 60, CAST(GETDATE() AS DATE))
    AND cea.EpiSlId = 1
    AND csv.SourceSystem = 'Abode'
    AND cea.EpiStatus NOT IN ('DELETED','PENDING','NON-ADMIT')
    AND (cev.CevDeleted <> 1 OR cev.CevDeleted IS NULL)
    AND cea.EpiEndOfEpisode <= CAST(GETDATE() - 1 AS DATE)

GROUP BY
    FORMAT(csv.CsvSchedDate, 'yyyy-MM'),
    CASE 
        WHEN CEA.EpiEndOfEpisode <= CAST(GETDATE() - 1 AS DATE)
            THEN 'Closed'
        ELSE 'Open'
    END

ORDER BY YearMonth;
