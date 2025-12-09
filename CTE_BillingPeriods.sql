DECLARE @StartDate DATE     = DATEADD(MONTH, -13, CAST(GETDATE() AS DATE)); -- rolling 13 months
DECLARE @EndDate   DATE     = DATEADD(DAY, 60, CAST(GETDATE() AS DATE));
DECLARE @ServiceLineId INT  = 1;
DECLARE @SourceSystem SYSNAME = 'Abode';

;WITH CTE_Episodes AS (
    SELECT e.EpiId
    FROM dbo.ClientEpisodesAll e
    WHERE e.EpiSlId = @ServiceLineId
      AND e.SourceSystem = @SourceSystem
      AND e.EpiStartOfEpisode >= @StartDate
),
CTE_EpisodeFs AS (
    SELECT 
        cefs.CefsEpiId AS EpiId, 
        cefs.CefsId,
        ins.InsuranceType
    FROM dbo.ClientEpisodeFs cefs
    INNER JOIN CTE_Episodes e 
        ON e.EpiId = cefs.CefsEpiId
    INNER JOIN dbo.ClientInsurance ci
        ON cefs.CefsCiId = ci.CiId
       AND ci.SourceSystem = @SourceSystem
    INNER JOIN dbo.InsurancePlan ins
        ON ci.CiPlanId = ins.PlanId
       AND ins.SourceSystem = @SourceSystem
    WHERE cefs.SourceSystem = @SourceSystem
      AND cefs.CefsActive = 'Y'
),
CTE_BillingPeriods AS (
    SELECT
        pp.PpId,
        pp.PpCefsId,
        pp.PpPeriodNumber,
        pp.PpStartDate,
        pp.PpEndDate,
        COALESCE(NULLIF(pp.PpCurrentHipps, ''), pp.PpInitialHipps) AS HippsCode,
        ef.EpiId,
        ef.InsuranceType,
        COALESCE(phc.PhClinicalGrouping, phi.PhClinicalGrouping) AS ClinicalGrouping,
        COALESCE(phc.PhTiming, phi.PhTiming) AS Timing
    FROM CTE_EpisodeFs ef
    INNER JOIN dbo.PdgmPeriod pp
        ON ef.CefsId = pp.PpCefsId
       AND pp.PpDeleted = 0
       AND pp.SourceSystem = @SourceSystem
    LEFT JOIN dbo.HCHBPdgmHipps phc WITH (NOLOCK) 
        ON pp.PpCurrentHipps = phc.Phhipps
       AND pp.SourceSystem = phc.SourceSystem
    LEFT JOIN dbo.HCHBPdgmHipps phi WITH (NOLOCK) 
        ON pp.PpInitialHipps = phi.Phhipps
       AND pp.SourceSystem = phi.SourceSystem
    WHERE pp.PpStartDate BETWEEN @StartDate AND @EndDate
),
CTE_BillingWithRates AS (
    SELECT
        bp.EpiId,
        bp.PpId,
        bp.PpPeriodNumber,
        bp.PpStartDate,
        bp.PpEndDate,
        bp.HippsCode,
        bp.InsuranceType,
        bp.ClinicalGrouping,
        bp.Timing,
        rp.Id AS RatePeriodId,
        rp.RpCode,
        rp.RpSoeEffectiveFrom AS EffectiveFrom,
        rp.RpSoeEffectiveTo   AS EffectiveTo,
        ROW_NUMBER() OVER (
            PARTITION BY bp.PpId
            ORDER BY rp.RpSoeEffectiveFrom ASC
        ) AS rn,
        CASE 
            WHEN bp.InsuranceType = 'COMMERCIAL INSURANCE-EPISODIC/CASE RATE' THEN
                CASE 
                    WHEN bp.ClinicalGrouping = 'Behavioral Health' AND bp.Timing = 'Early' THEN 1327.85
                    WHEN bp.ClinicalGrouping = 'Behavioral Health' AND bp.Timing = 'Late'  THEN 929.49
                    WHEN bp.ClinicalGrouping = 'Complex Nursing Interventions' AND bp.Timing = 'Early' THEN 1176.38
                    WHEN bp.ClinicalGrouping = 'Complex Nursing Interventions' AND bp.Timing = 'Late'  THEN 705.83
                    WHEN bp.ClinicalGrouping = 'MMTA - Cardiac and Circulatory' AND bp.Timing = 'Early' THEN 1436.46
                    WHEN bp.ClinicalGrouping = 'MMTA - Cardiac and Circulatory' AND bp.Timing = 'Late'  THEN 1005.52
                    WHEN bp.ClinicalGrouping = 'MMTA - Endocrine' AND bp.Timing = 'Early' THEN 1386.92
                    WHEN bp.ClinicalGrouping = 'MMTA - Endocrine' AND bp.Timing = 'Late'  THEN 1248.23
                    WHEN bp.ClinicalGrouping = 'MMTA - GI/GU' AND bp.Timing = 'Early' THEN 1438.62
                    WHEN bp.ClinicalGrouping = 'MMTA - GI/GU' AND bp.Timing = 'Late'  THEN 1007.03
                    WHEN bp.ClinicalGrouping = 'MMTA - Infectious Disease' AND bp.Timing = 'Early' THEN 1426.07
                    WHEN bp.ClinicalGrouping = 'MMTA - Infectious Disease' AND bp.Timing = 'Late'  THEN 998.25
                    WHEN bp.ClinicalGrouping = 'MMTA - Other' AND bp.Timing = 'Early' THEN 1389.80
                    WHEN bp.ClinicalGrouping = 'MMTA - Other' AND bp.Timing = 'Late'  THEN 972.86
                    WHEN bp.ClinicalGrouping = 'MMTA - Respiratory' AND bp.Timing = 'Early' THEN 1446.23
                    WHEN bp.ClinicalGrouping = 'MMTA - Respiratory' AND bp.Timing = 'Late'  THEN 1012.36
                    WHEN bp.ClinicalGrouping = 'MMTA - Surgical Aftercare' AND bp.Timing = 'Early' THEN 1441.41
                    WHEN bp.ClinicalGrouping = 'MMTA - Surgical Aftercare' AND bp.Timing = 'Late'  THEN 1153.13
                    WHEN bp.ClinicalGrouping = 'MS Rehab' AND bp.Timing = 'Early' THEN 1438.22
                    WHEN bp.ClinicalGrouping = 'MS Rehab' AND bp.Timing = 'Late'  THEN 1150.57
                    WHEN bp.ClinicalGrouping = 'Neuro Rehab' AND bp.Timing = 'Early' THEN 1617.37
                    WHEN bp.ClinicalGrouping = 'Neuro Rehab' AND bp.Timing = 'Late'  THEN 1293.90
                    WHEN bp.ClinicalGrouping = 'Wounds' AND bp.Timing = 'Early' THEN 1521.49
                    WHEN bp.ClinicalGrouping = 'Wounds' AND bp.Timing = 'Late'  THEN 1369.35
                    ELSE 0.00
                END
            ELSE 0.00
        END AS UHC_Reimbursement
    FROM CTE_BillingPeriods bp
    LEFT JOIN dbo.RatePeriod rp
        ON bp.HippsCode = rp.RpCode
       AND bp.PpStartDate >= rp.RpSoeEffectiveFrom
       AND (bp.PpStartDate <= rp.RpSoeEffectiveTo OR rp.RpSoeEffectiveTo IS NULL)
       AND rp.RpActive = 'Y'
)
SELECT *
FROM CTE_BillingWithRates
WHERE rn = 1
ORDER BY EpiId DESC, PpPeriodNumber;








