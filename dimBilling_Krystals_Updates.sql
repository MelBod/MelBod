-- 1) Rate period lookup by episode -> period -> rate period
WITH rp
AS (
     SELECT DISTINCT cea.EpiId AS EpisodeId
          ,pp.PpPeriodNumber
          ,pp.PpStartDate
          ,pp.PpEndDate
          ,rp.RpId
          ,rp.RpCode
          ,rp.RpSoeEffectiveFrom
          ,rp.RpSoeEffectiveTo
          ,cea.SourceSystem
     
     FROM dbo.ClientEpisodesAll AS cea
     
     INNER JOIN dbo.ClientEpisodeFs AS cefs
          ON cea.EpiId = cefs.CefsEpiId
               AND cea.SourceSystem = cefs.SourceSystem
     
     INNER JOIN dbo.PdgmPeriod AS pp
          ON cefs.CefsId = pp.PpCefsId
               AND pp.PpDeleted = 0
               AND cefs.SourceSystem = pp.SourceSystem
     
     INNER JOIN dbo.RatePeriod AS rp
          ON pp.PpStartDate BETWEEN rp.RpSoeEffectiveFrom
                    AND rp.RpSoeEffectiveTo
               AND rp.RpActive = 'Y'
               AND rp.RpSltId = 1 -- Home Health Service Line Type
               AND rp.RpRptId = 5 -- Rate Period Type
               AND cea.SourceSystem = rp.SourceSystem
     
     WHERE cea.EpiSlId = 1 -- Home Health
     )
     ,
     -- 2) Choose earliest Rate Period per episode/period
pd
AS (
     SELECT t1.EpisodeId
          ,t1.PpPeriodNumber
          ,t1.PpStartDate
          ,t1.PpEndDate
          ,t1.RpId AS RatePeriodId
          ,t1.RpCode
          ,t1.RpSoeEffectiveFrom
          ,t1.RpSoeEffectiveTo
          ,t1.SourceSystem
     
     FROM rp AS t1
     
     INNER JOIN (
          SELECT EpisodeId
               ,PpPeriodNumber
               ,MIN(RpSoeEffectiveFrom) AS MinEffectiveFrom
               ,SourceSystem
          
          FROM rp
          
          GROUP BY EpisodeId
               ,PpPeriodNumber
               ,SourceSystem
          ) AS t2
          ON t1.EpisodeId = t2.EpisodeId
               AND t1.PpPeriodNumber = t2.PpPeriodNumber
               AND t1.RpSoeEffectiveFrom = t2.MinEffectiveFrom
               AND t1.SourceSystem = t2.SourceSystem
     )
     ,
     -- 3) HIPPS / LUPA mapping per PDGM Period (Driving Data)
h
AS (
     SELECT DISTINCT pp.PpId AS PPId
          ,CASE 
               WHEN pp.PpCurrentHipps <> ''
                    THEN pp.PpCurrentHipps
               WHEN pp.PpInitialHipps <> ''
                    THEN pp.PpInitialHipps
               ELSE NULL
               END AS HIPPS
          ,COALESCE(phc.PhLupaThreshold, phi.PhLupaThreshold) AS LupaThresholdOld
          ,COALESCE(phc.PhClinicalGrouping, phi.PhClinicalGrouping) AS ClinicalGrouping
          ,COALESCE(phc.PhTiming, phi.PhTiming) AS Timing
          ,COALESCE(phc.PhFunctionalImpairmentLevel, phi.PhFunctionalImpairmentLevel) AS FunctionalImpLevel
          ,COALESCE(phc.PhComorbidityAdjustment, phi.PhComorbidityAdjustment) AS ComorbidityAdjustment
          ,COALESCE(phc.PhCaseMixWeight, phi.PhCaseMixWeight) AS CaseMixWeight
          ,cea.EpiId AS EpisodeId
          ,cefs.CefsPsId AS BPInsuranceId
          ,pp.PpStartDate AS BPStartDate
          ,pp.PpEndDate AS BPEndDate
          ,pp.PpPeriodNumber AS BPSeq
          ,ca.CaId AS AdmissionId
          ,cefs.CefsPsId AS InsuranceId
          ,cea.SourceSystem
     
     FROM dbo.ClientEpisodesAll AS cea WITH (NOLOCK)
     
     INNER JOIN dbo.ClientEpisodeFs AS cefs WITH (NOLOCK)
          ON cea.EpiId = cefs.CefsEpiId
               AND cea.SourceSystem = cefs.SourceSystem
     
     INNER JOIN dbo.HCHBPdgmPeriod AS pp WITH (NOLOCK)
          ON cefs.CefsId = pp.PpCefsId
               AND cefs.SourceSystem = pp.SourceSystem
     
     LEFT JOIN dbo.HCHBClientAdmission AS ca WITH (NOLOCK)
          ON cea.EpiPaId = ca.CaPaId
               AND cea.EpiSlId = ca.CaSlId
               AND cea.EpiSOCDate = ca.CaSOCDate
               AND cea.SourceSystem = ca.SourceSystem
     
     LEFT JOIN pd AS erp
          ON cea.EpiId = erp.EpisodeId
               AND pp.PpPeriodNumber = erp.PpPeriodNumber
               AND cea.SourceSystem = erp.SourceSystem
     
     LEFT JOIN dbo.HCHBPdgmHipps AS phc WITH (NOLOCK)
          ON pp.PpCurrentHipps = phc.PhHipps
               AND erp.RatePeriodId = phc.PhRpId
               AND pp.SourceSystem = phc.SourceSystem
     
     LEFT JOIN dbo.HCHBPdgmHipps AS phi WITH (NOLOCK)
          ON pp.PpInitialHipps = phi.PhHipps
               AND erp.RatePeriodId = phi.PhRpId
               AND pp.SourceSystem = phi.SourceSystem
     
     WHERE pp.PpDeleted = 0
          AND cea.EpiStatus NOT IN (
               'DELETED'
               ,'PENDING'
               ,'NON-ADMIT'
               )
          AND cea.EpiSlId = 1
		  AND pp.PpStartDate >= DATEADD(MONTH, -13, DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0))
     )
     ,
     -- 4) Initial Billing Period Requests
BP_Requests
AS (
     SELECT r.ReqId
          ,r.EpiId
          ,de.StartOfEpisodeDate
          ,de.EndOfEpisodeDate
          ,r.ServiceLineId
          ,r.ShiftDate
          ,FORMAT(r.ShiftDate, 'yyyyMMdd') AS ShiftDateKey
          ,r.ShiftHrs
          ,jd.JdCode
          ,jd.JdDescription AS Discipline
          ,r.RateType
          ,ISNULL(r.FlatType, '*') AS ServiceCode
          ,CASE 
               WHEN sc.ScBillable = 'Y'
                    THEN 1
               ELSE 0
               END AS ServiceBillable
          ,ef.BPSeq
          ,CASE 
               WHEN ef.BPSeq IS NOT NULL
                    THEN CONVERT(VARCHAR(20), r.EpiId) + '-' + CONVERT(VARCHAR(10), ef.BPSeq)
               END AS BPKey
          ,r.NumberRequested AS Requested
          ,r.OrderID AS RequestOrderId
          ,r.Scheduled
          ,r.NoNeedNum
          ,r.TransferStatus
     
     FROM dbo.Request AS r
     
     INNER JOIN dbo.JobDescriptions AS jd
          ON r.JobDId = jd.JdId
     
     LEFT JOIN dbo.ServiceCodes AS sc
          ON sc.ScCode = r.FlatType
     
     LEFT JOIN dbo.dimEpisode AS de
          ON r.EpiId = de.EpisodeId
               AND r.SourceSystem = de.SourceSystem
     
     CROSS APPLY (
          SELECT CASE 
                    WHEN DATEDIFF(DAY, de.StartOfEpisodeDate, r.ShiftDate) <= 30
                         THEN 1
                    WHEN DATEDIFF(DAY, de.StartOfEpisodeDate, r.ShiftDate) >= 31
                         THEN 2
                    END AS BPSeq
          ) AS ef
     
     WHERE NOT (
               r.NumberRequested > (r.Scheduled + r.NoNeedNum)
               AND r.TransferStatus = 3
               )
          AND r.ServiceLineId = 1
          AND r.NoNeedNum = 0
          AND r.TransferStatus <> 3
          AND sc.ScBillable = 'Y'
          AND r.Scheduled = 0
     )
     ,
     -- 5) BP Request Summary (deduped)
BP_Requests_Summary
AS (
     SELECT BPKey
          ,BPSeq AS PpPeriodNumber
          ,SUM(Requested) AS Requests
     
     FROM (
          SELECT DISTINCT BPKey
               ,BPSeq
               ,ReqId
               ,Requested
               ,ServiceBillable
          
          FROM BP_Requests
          
          WHERE BPKey IS NOT NULL
          ) AS dedup
     
     GROUP BY BPKey
          ,BPSeq
     )
     ,
     -- 6) TaskDetails (visit-level)
TaskDetails
AS (
     SELECT csv.CsvId AS ScheduledVisitId
          ,cev.CevId AS VisitId
          ,cea.EpiId AS EpisodeId
          ,csv.CsvLastUpdate AS LastUpdateDate
          ,MAX(csv.CsvLastUpdate) OVER (
               PARTITION BY csv.CsvEpiId
               ,csv.CsvSchedDate
               ,csv.CsvId
               ,sc.ScCode
               ) AS MaxUpdateDate
          ,CASE 
               WHEN EBP.BPSeq IS NOT NULL
                    THEN CAST(cea.EpiId AS VARCHAR(20)) + '-' + CAST(EBP.BPSeq AS VARCHAR(20))
               END AS BPKey
          ,EBP.BPSeq AS BillingPeriodSequence
          ,CONVERT(CHAR(8), EBP.BPStartDate, 112) AS BillingPeriodStartDate
          ,CONVERT(CHAR(8), EBP.BPEndDate, 112) AS BillingPeriodEndDate
          ,CONVERT(CHAR(8), CEA.EpiStartOfEpisode, 112) AS EpisodeStartDate
          ,CONVERT(CHAR(8), CEA.EpiEndOfEpisode, 112) AS EpisodeEndDate
          ,CONVERT(CHAR(8), CEA.EpiSocDate, 112) AS StartOfCareDate
          ,1 AS TaskCount
          ,CASE 
               WHEN sc.ScBillable = 'Y'
                    THEN CASE 
                              WHEN MAX(CASE 
                                             WHEN vs.VsDescription = 'COMPLETED'
                                                  THEN 1
                                             ELSE 0
                                             END) OVER (
                                        PARTITION BY csv.CsvEpiId
                                        ,csv.CsvVisitNumber
                                        ,csv.CsvScId
                                        ,sc.ScCode
                                        ) = 1
                                   AND vs.VsDescription = 'COMPLETED'
                                   THEN CASE 
                                             WHEN sc.ScCode LIKE '%PRN%'
                                                  THEN CASE 
                                                            WHEN vs.VsDescription IN (
                                                                      'COMPLETED'
                                                                      ,'MISSED'
                                                                      )
                                                                 THEN 1
                                                            ELSE 0
                                                            END
                                             ELSE 1
                                             END
                              WHEN MAX(CASE 
                                             WHEN vs.VsDescription = 'COMPLETED'
                                                  THEN 1
                                             ELSE 0
                                             END) OVER (
                                        PARTITION BY csv.CsvEpiId
                                        ,csv.CsvVisitNumber
                                        ,csv.CsvScId
                                        ,sc.ScCode
                                        ) = 0
                                   AND ROW_NUMBER() OVER (
                                        PARTITION BY csv.CsvEpiId
                                        ,csv.CsvVisitNumber
                                        ,csv.CsvScId
                                        ,sc.ScCode ORDER BY csv.CsvLastUpdate DESC
                                             ,csv.CsvSchedDate DESC
                                        ) = 1
                                   AND (
                                        sc.ScCode NOT LIKE '%PRN%'
                                        OR (
                                             sc.ScCode LIKE '%PRN%'
                                             AND vs.VsDescription IN (
                                                  'COMPLETED'
                                                  ,'MISSED'
                                                  )
                                             )
                                        )
                                   THEN CASE 
                                             WHEN sc.ScCode LIKE '%PRN%'
                                                  THEN CASE 
                                                            WHEN vs.VsDescription IN (
                                                                      'COMPLETED'
                                                                      ,'MISSED'
                                                                      )
                                                                 THEN 1
                                                            ELSE 0
                                                            END
                                             ELSE 1
                                             END
                              ELSE 0
                              END
               ELSE 0
               END AS InHomeVisits_VisitNumber
          ,CASE 
               WHEN sc.ScBillable = 'Y'
                    AND vs.VsDescription NOT IN (
                         'COMPLETED'
                         ,'MISSED'
                         ,'DECLINED'
                         )
                    AND sc.ScCode NOT LIKE '%PRN%'
                    AND ROW_NUMBER() OVER (
                         PARTITION BY csv.CsvEpiId
                         ,csv.CsvVisitNumber
                         ,csv.CsvScId
                         ,sc.ScCode ORDER BY csv.CsvLastUpdate DESC
                              ,csv.CsvSchedDate DESC
                         ) = 1
                    THEN 1
               ELSE 0
               END AS ScheduledVisits
          ,CASE 
               WHEN vs.VsDescription = 'COMPLETED'
                    THEN 1
               WHEN csv.CsvSchedDate BETWEEN cea.EpiStartOfEpisode
                         AND cea.EpiEndOfEpisode
                    THEN 1
               ELSE 0
               END AS VisitBetweenSOEandEOE
          ,CASE 
               WHEN vs.VsDescription = 'COMPLETED'
                    AND sc.ScCode NOT LIKE '%66%'
                    AND cev.CevBillable = 1
                    THEN 1
               ELSE 0
               END AS CompletedVisits
          ,CASE 
               WHEN cev.CevBillable = 1
                    THEN 1
               ELSE 0
               END AS VisitBillable
          ,CASE 
               WHEN sc.ScBillable = 'Y'
                    THEN 1
               ELSE 0
               END AS ServiceBillable
          ,CASE 
               WHEN sc.ScPayable = 'Y'
                    THEN 1
               ELSE 0
               END AS Payable
          ,CASE 
               WHEN EBP.BPEndDate >= CAST(GETDATE() - 1 AS DATE)
                    THEN 'Open'
               ELSE 'Closed'
               END AS BP_OpenClosedFlag
          ,sc.ScDesc AS TaskDesc
          ,sc.ScVisitType AS TaskType
          ,sc.ScCode AS TaskCode
          ,sc.ScJdCode AS TaskJobCode
          ,d.DscDesc AS Discipline
          ,sc.ScProductivityPoints AS ProductivityPts
          ,vs.VsDescription AS TaskStatus
          ,vmr.VmDesc AS VisitMissedReason
          ,p.PatientId
          ,p.Address1 AS PatientAddress
          ,cefs.CefsPsid AS InsuranceId
          ,i.InsuranceTypeId
          ,i.InsuranceType
          ,cea.EpiBranchcode AS BranchCode
          ,b.Id AS skOrgKey
          ,RIGHT(b.ForeignCode, 5) AS [Location]
          ,cea.EpiSlId
          ,EBP.HIPPS
          ,CASE 
               WHEN COALESCE(i.InsuranceTypeId, cefs.CefsPsid) = 25024
                    THEN 4
               ELSE EBP.LupaThresholdOld
               END AS LupaThreshold
          ,EBP.ClinicalGrouping
          ,EBP.Timing
          ,EBP.FunctionalImpLevel
          ,EBP.ComorbidityAdjustment
          ,EBP.CaseMixWeight
          ,csv.SourceSystem
          ,cev.CevDeleted
          ,cea.EpiStatus
          ,csv.CsvVisitNumber
          ,cea.EpiLastName
          ,cea.EpiFirstName
          ,cea.EpiMI
          ,CONCAT_WS(' ', CONCAT (
                    cea.EpiLastName
                    ,', '
                    ,cea.EpiFirstName
                    ), cea.EpiMI) AS PatientName
     
     FROM dbo.ClientSchedVisits AS csv WITH (NOLOCK)
     
     INNER JOIN dbo.VisitStatuses AS vs WITH (NOLOCK)
          ON csv.CsvStatus = vs.VsStatus
               AND csv.SourceSystem = vs.SourceSystem
     
     INNER JOIN dbo.ServiceCodes AS sc WITH (NOLOCK)
          ON csv.CsvScid = sc.Scid
               AND csv.SourceSystem = sc.SourceSystem
     
     INNER JOIN dbo.Disciplines AS d WITH (NOLOCK)
          ON sc.ScDiscipline = d.DscCode
               AND sc.SourceSystem = d.SourceSystem
     
     INNER JOIN dbo.ClientEpisodesAll AS cea WITH (NOLOCK)
          ON csv.CsvEpiId = cea.EpiId
               AND csv.SourceSystem = cea.SourceSystem
     
     INNER JOIN dbo.dimBranch AS b WITH (NOLOCK)
          ON cea.EpiBranchcode = b.BranchCode
               AND cea.SourceSystem = b.SourceSystem
     
     INNER JOIN dbo.dimPatient AS p WITH (NOLOCK)
          ON cea.EpiPaId = p.PatientId
               AND cea.SourceSystem = p.SourceSystem
     
     LEFT JOIN h AS EBP
          ON cea.EpiId = EBP.EpisodeId
               AND cea.SourceSystem = EBP.SourceSystem
               AND csv.CsvSchedDate BETWEEN EBP.BPStartDate
                    AND EBP.BPEndDate
     
     LEFT JOIN dbo.ClientEpisodeVisitsAll AS cev WITH (NOLOCK)
          ON csv.CsvId = cev.CevCsvId
               AND csv.SourceSystem = cev.SourceSystem
               AND cev.CevDeleted = 0
     
     LEFT JOIN dbo.ClientEpisodeFs AS cefs WITH (NOLOCK)
          ON cea.EpiId = cefs.CefsEpiId
               AND cefs.CefsPs = 'P'
               AND cefs.CefsActive = 'Y'
               AND cea.SourceSystem = cefs.SourceSystem
     
     LEFT JOIN dbo.VisitMissedReasons AS vmr WITH (NOLOCK)
          ON csv.CsvVmId = vmr.VmId
               AND csv.SourceSystem = vmr.SourceSystem
     
     LEFT JOIN dimInsurance AS i WITH (NOLOCK)
          ON cefs.CefsPsid = i.InsuranceId
               AND cefs.SourceSystem = i.SourceSystem
     
     WHERE csv.CsvSchedDate >= DATEADD(MONTH, - 13, DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0))
          AND csv.CsvSchedDate <= DATEADD(DAY, 60, GETDATE())
          AND cea.EpiSlId = 1
          AND cea.EpiStatus NOT IN (
               'DELETED'
               ,'PENDING'
               ,'NON-ADMIT'
               )
          AND (
               cev.CevDeleted <> 1
               OR cev.CevDeleted IS NULL
               )
     )
     ,
     -- 7) Aggregate TaskDetails to Billing Period
TD_Agg
AS (
     SELECT td.EpisodeId
          ,td.BPKey
          ,td.BillingPeriodStartDate
          ,td.BillingPeriodEndDate
          ,td.EpisodeStartDate
          ,td.EpisodeEndDate
          ,td.StartOfCareDate
          ,td.BillingPeriodSequence
          ,td.PatientId
          ,MAX(td.PatientName) AS PatientName
          ,MAX(td.PatientAddress) AS PatientAddress
          ,MAX(td.InsuranceId) AS InsuranceId
          ,MAX(td.InsuranceTypeId) AS InsuranceTypeId
          ,MAX(td.InsuranceType) AS InsuranceType
          ,MAX(td.BranchCode) AS BranchCode
          ,MAX(td.[Location]) AS [Location]
          ,MAX(td.HIPPS) AS HIPPS
          ,MAX(td.LupaThreshold) AS LupaThreshold
          ,MAX(td.ClinicalGrouping) AS ClinicalGrouping
          ,MAX(td.Timing) AS Timing
          ,MAX(td.FunctionalImpLevel) AS FunctionalImpLevel
          ,MAX(td.ComorbidityAdjustment) AS ComorbidityAdjustment
          ,MAX(td.CaseMixWeight) AS CaseMixWeight
          ,MAX(td.BP_OpenClosedFlag) AS BP_OpenClosedFlag
          ,MAX(td.EpiStatus) AS EpiStatus
          ,SUM(COALESCE(td.ScheduledVisits, 0)) AS ScheduledVisits
          ,SUM(CASE 
                    WHEN td.TaskCode LIKE '%66%'
                         THEN 0
                    WHEN td.TaskStatus = 'MISSED'
                         AND td.ServiceBillable = 1
                         THEN 1
                    ELSE 0
                    END) AS MissedVisits
          ,SUM(CASE 
                    WHEN td.VisitBillable = 1
                         THEN 1
                    ELSE 0
                    END) AS TotalBillableVisits
          ,SUM(CASE 
                    WHEN td.BP_OpenClosedFlag = 'Open'
                         THEN td.CompletedVisits
                    ELSE 0
                    END) AS TotalCompleted_Open
          ,SUM(CASE 
                    WHEN td.Discipline = 'PHYSICAL THERAPIST'
                         AND td.BP_OpenClosedFlag = 'Closed'
                         THEN td.CompletedVisits
                    ELSE 0
                    END) AS PT
          ,SUM(CASE 
                    WHEN td.Discipline = 'OCCUPATIONAL THERAPIST'
                         AND td.BP_OpenClosedFlag = 'Closed'
                         THEN td.CompletedVisits
                    ELSE 0
                    END) AS OT
          ,SUM(CASE 
                    WHEN td.Discipline = 'SKILLED NURSE'
                         AND td.BP_OpenClosedFlag = 'Closed'
                         THEN td.CompletedVisits
                    ELSE 0
                    END) AS SN
          ,SUM(CASE 
                    WHEN td.Discipline = 'SPEECH THERAPIST'
                         AND td.BP_OpenClosedFlag = 'Closed'
                         THEN td.CompletedVisits
                    ELSE 0
                    END) AS ST
          ,SUM(CASE 
                    WHEN td.Discipline = 'MEDICAL SOCIAL WORKER'
                         AND td.BP_OpenClosedFlag = 'Closed'
                         THEN td.CompletedVisits
                    ELSE 0
                    END) AS MSW
          ,SUM(CASE 
                    WHEN td.Discipline = 'HOME HEALTH AIDE'
                         AND td.BP_OpenClosedFlag = 'Closed'
                         THEN td.CompletedVisits
                    ELSE 0
                    END) AS HHA
          ,SUM(CASE 
                    WHEN td.BP_OpenClosedFlag = 'Closed'
                         THEN td.CompletedVisits
                    ELSE 0
                    END) AS TotalCompleted_Closed
          ,SUM(CASE 
                    WHEN td.Discipline = 'PHYSICAL THERAPIST'
                         AND td.BP_OpenClosedFlag = 'Open'
                         THEN td.InHomeVisits_VisitNumber
                    ELSE 0
                    END) AS PT_Open
          ,SUM(CASE 
                    WHEN td.Discipline = 'OCCUPATIONAL THERAPIST'
                         AND td.BP_OpenClosedFlag = 'Open'
                         THEN td.InHomeVisits_VisitNumber
                    ELSE 0
                    END) AS OT_Open
          ,SUM(CASE 
                    WHEN td.Discipline = 'SKILLED NURSE'
                         AND td.BP_OpenClosedFlag = 'Open'
                         THEN td.InHomeVisits_VisitNumber
                    ELSE 0
                    END) AS SN_Open
          ,SUM(CASE 
                    WHEN td.Discipline = 'SPEECH THERAPIST'
                         AND td.BP_OpenClosedFlag = 'Open'
                         THEN td.InHomeVisits_VisitNumber
                    ELSE 0
                    END) AS ST_Open
          ,SUM(CASE 
                    WHEN td.Discipline = 'MEDICAL SOCIAL WORKER'
                         AND td.BP_OpenClosedFlag = 'Open'
                         THEN td.InHomeVisits_VisitNumber
                    ELSE 0
                    END) AS MSW_Open
          ,SUM(CASE 
                    WHEN td.Discipline = 'HOME HEALTH AIDE'
                         AND td.BP_OpenClosedFlag = 'Open'
                         THEN td.InHomeVisits_VisitNumber
                    ELSE 0
                    END) AS HHA_Open
          ,SUM(CASE 
                    WHEN td.BP_OpenClosedFlag = 'Open'
                         THEN td.InHomeVisits_VisitNumber
                    ELSE 0
                    END) AS TotalOpen
          ,SUM(CASE 
                    WHEN td.ServiceBillable = 1
                         THEN 1
                    ELSE 0
                    END) AS ServiceBillable
          ,-- for HasBillableService
          SUM(CASE 
                    WHEN td.TaskStatus IN (
                              'Missed'
                              ,'Rescheduled'
                              ,'Office Reassigned'
                              ,'Declined'
                              ,'Requested'
                              )
                         THEN 1
                    ELSE 0
                    END) AS AnyOpenNonCompletionFlags
          ,SUM(CASE 
                    WHEN td.CompletedVisits = 1
                         AND td.ServiceBillable = 1
                         THEN 1
                    ELSE 0
                    END) AS BillableCompletionsCount
     
     FROM TaskDetails td
     
     GROUP BY td.EpisodeId
          ,td.BPKey
          ,td.BillingPeriodStartDate
          ,td.BillingPeriodEndDate
          ,td.EpisodeStartDate
          ,td.EpisodeEndDate
          ,td.StartOfCareDate
          ,td.BillingPeriodSequence
          ,td.PatientId
     )
     ,
     -- 8) Final — PDGM drives; LEFT JOIN visits and requests
Final_AllPDGM
AS (
     SELECT h.EpisodeId
          ,CAST(h.EpisodeId AS VARCHAR(20)) + '-' + CAST(h.BPSeq AS VARCHAR(20)) AS BPKey
          ,CONVERT(CHAR(8), h.BPStartDate, 112) AS skBillingPeriodStartDateKey
          ,CONVERT(CHAR(8), h.BPEndDate, 112) AS skBillingPeriodEndDateKey
          ,CONVERT(CHAR(8), cea.EpiStartOfEpisode, 112) AS skEpisodeStartDateKey
          ,CONVERT(CHAR(8), cea.EpiEndOfEpisode, 112) AS skEpisodeEndDateKey
          ,CONVERT(CHAR(8), cea.EpiSocDate, 112) AS skStartOfCareKey
          ,h.BPSeq AS BillingPeriodSequence
          ,p.PatientId
          ,cea.EpiBranchcode + '000' + CAST(p.PatientId AS VARCHAR(20)) + '0' + CAST(cea.EpiSlId AS VARCHAR(10)) AS MRN
          ,CAST(p.PatientId AS VARCHAR(50)) + '_' + h.SourceSystem AS PatientSystemId
          ,CONCAT_WS(' ', CONCAT (
                    cea.EpiLastName
                    ,', '
                    ,cea.EpiFirstName
                    ), cea.EpiMI) AS PatientName
          ,p.Address1 AS PatientAddress
          ,cefs.CefsPsId AS InsuranceId
          ,i.InsuranceTypeId
          ,i.InsuranceType
          ,cea.EpiBranchcode AS BranchCode
          ,RIGHT(b.ForeignCode, 5) AS [Location]
          ,h.HIPPS
          ,CASE 
               WHEN COALESCE(i.InsuranceTypeId, cefs.CefsPsId) = 25024
                    THEN 4
               ELSE h.LupaThresholdOld
               END AS LupaThreshold
          ,h.ClinicalGrouping
          ,h.Timing
          ,h.FunctionalImpLevel
          ,h.ComorbidityAdjustment
          ,h.CaseMixWeight
          ,CASE 
               WHEN h.BPEndDate >= CAST(GETDATE() - 1 AS DATE)
                    THEN 'Open'
               ELSE 'Closed'
               END AS BP_OpenClosedFlag
          ,cea.EpiStatus
          ,COALESCE(brs.Requests, 0) AS Requests
          ,COALESCE(tda.MissedVisits, 0) AS MissedVisits
          ,COALESCE(tda.ScheduledVisits, 0) AS ScheduledVisits
          ,CASE 
               WHEN COALESCE(tda.ServiceBillable, 0) > 0
                    THEN 'Y'
               ELSE 'N'
               END AS HasBillableService
          ,COALESCE(tda.TotalBillableVisits, 0) AS TotalBillableVisits
          ,FORMAT(h.BPStartDate, 'M/dd/yyyy') AS BillingPeriodStartDate
          ,FORMAT(h.BPEndDate, 'M/dd/yyyy') AS BillingPeriodEndDate
          ,FORMAT(cea.EpiStartOfEpisode, 'M/dd/yyyy') AS EpisodeStartDate
          ,FORMAT(cea.EpiEndOfEpisode, 'M/dd/yyyy') AS EpisodeEndDate
          ,FORMAT(cea.EpiSocDate, 'M/dd/yyyy') AS SOCDate
          ,COALESCE(tda.PT, 0) AS PT
          ,COALESCE(tda.OT, 0) AS OT
          ,COALESCE(tda.SN, 0) AS SN
          ,COALESCE(tda.ST, 0) AS ST
          ,COALESCE(tda.MSW, 0) AS MSW
          ,COALESCE(tda.HHA, 0) AS HHA
          ,COALESCE(tda.TotalCompleted_Closed, 0) AS TotalCompleted_Closed
          ,CASE 
               WHEN h.BPEndDate < CAST(GETDATE() - 1 AS DATE) -- CLOSED
                    AND COALESCE(tda.TotalCompleted_Closed, 0) > 0
                    AND COALESCE(tda.TotalCompleted_Closed, 0) < (
                         CASE 
                              WHEN COALESCE(i.InsuranceTypeId, cefs.CefsPsId) = 25024
                                   THEN 4
                              ELSE h.LupaThresholdOld
                              END
                         )
                    THEN 1
               ELSE 0
               END AS IsLupaBP
          ,COALESCE(tda.PT_Open, 0) AS PT_Open
          ,COALESCE(tda.OT_Open, 0) AS OT_Open
          ,COALESCE(tda.SN_Open, 0) AS SN_Open
          ,COALESCE(tda.ST_Open, 0) AS ST_Open
          ,COALESCE(tda.MSW_Open, 0) AS MSW_Open
          ,COALESCE(tda.HHA_Open, 0) AS HHA_Open
          ,COALESCE(tda.TotalOpen, 0) AS TotalOpen
          ,COALESCE(tda.TotalCompleted_Open, 0) AS TotalCompleted_Open
          ,CASE 
               WHEN h.BPEndDate >= CAST(GETDATE() - 1 AS DATE) -- OPEN
                    AND COALESCE(tda.TotalOpen, 0) >= 1 -- must have activity
                    AND COALESCE(tda.TotalOpen, 0) < (
                         CASE 
                              WHEN COALESCE(i.InsuranceTypeId, cefs.CefsPsId) = 25024
                                   THEN 4
                              ELSE h.LupaThresholdOld
                              END
                         )
                    THEN 1
               ELSE 0
               END AS IsLupaBP_Open
          ,CASE 
               WHEN h.BPEndDate >= CAST(GETDATE() - 1 AS DATE) -- OPEN
                    AND COALESCE(tda.BillableCompletionsCount, 0) = 0 -- no completed billable visits
                    AND (
                         COALESCE(tda.TotalOpen, 0) > 0 -- some open visits but none completed
                         OR COALESCE(brs.Requests, 0) > 0 -- or requests exist
                         OR COALESCE(tda.ServiceBillable, 0) = 0 -- or NO visit-level records at all (PDGM-only)
                         )
                    THEN 1
               ELSE 0
               END AS GhostBillingPeriodOpen
          ,CASE 
               WHEN h.BPEndDate < CAST(GETDATE() - 1 AS DATE) -- CLOSED
                    AND COALESCE(tda.TotalCompleted_Closed, 0) = 0
                    THEN 1
               ELSE 0
               END AS GhostBillingPeriodClosed
     
     FROM h
     
     INNER JOIN dbo.ClientEpisodesAll AS cea WITH (NOLOCK)
          ON h.EpisodeId = cea.EpiId
               AND h.SourceSystem = cea.SourceSystem
     
     INNER JOIN dbo.dimPatient AS p WITH (NOLOCK)
          ON cea.EpiPaId = p.PatientId
               AND cea.SourceSystem = p.SourceSystem
     
     INNER JOIN dbo.dimBranch AS b WITH (NOLOCK)
          ON cea.EpiBranchcode = b.BranchCode
               AND cea.SourceSystem = b.SourceSystem
     
     LEFT JOIN dbo.ClientEpisodeFs AS cefs WITH (NOLOCK)
          ON cea.EpiId = cefs.CefsEpiId
               AND cefs.CefsPs = 'P'
               AND cefs.CefsActive = 'Y'
               AND cea.SourceSystem = cefs.SourceSystem
     
     LEFT JOIN dimInsurance AS i WITH (NOLOCK)
          ON cefs.CefsPsid = i.InsuranceId
               AND cefs.SourceSystem = i.SourceSystem
     
     LEFT JOIN TD_Agg AS tda
          ON tda.EpisodeId = h.EpisodeId
               AND tda.BPKey = CAST(h.EpisodeId AS VARCHAR(20)) + '-' + CAST(h.BPSeq AS VARCHAR(20))
     
     LEFT JOIN BP_Requests_Summary AS brs
          ON brs.BPKey = CAST(h.EpisodeId AS VARCHAR(20)) + '-' + CAST(h.BPSeq AS VARCHAR(20))
     )
     ,
     -- 9) Final filter
Final
AS (
     SELECT *
     
     FROM Final_AllPDGM
     
     WHERE InsuranceType IN (
               'COMMERCIAL INSURANCE-EPISODIC'
               ,'MEDICARE'
               ,'MEDICARE REPLACEMENT - EPISODIC'
               ,'COMMERCIAL INSURANCE-EPISODIC/CASE RATE'
               )
          --AND EpisodeId = 930116
     )

-- 10) Final SELECT
SELECT f.EpisodeId
     ,f.BPKey
     ,f.skBillingPeriodStartDateKey
     ,f.skBillingPeriodEndDateKey
     ,f.skEpisodeStartDateKey
     ,f.skEpisodeEndDateKey
     ,f.skStartOfCareKey
     ,f.MRN
     ,f.BillingPeriodSequence
     ,f.PatientId
     ,f.PatientName
     ,f.PatientSystemId
     ,f.PatientAddress
     ,f.InsuranceId
     ,f.InsuranceTypeId
     ,f.InsuranceType
     ,f.BranchCode
     ,f.[Location]
     ,f.HIPPS
     ,f.LupaThreshold
     ,f.ClinicalGrouping
     ,f.Timing
     ,f.FunctionalImpLevel
     ,f.ComorbidityAdjustment
     ,f.CaseMixWeight
     ,f.BP_OpenClosedFlag
     ,f.EpiStatus
     ,f.Requests
     ,f.MissedVisits
     ,f.ScheduledVisits
     ,f.HasBillableService
     ,f.TotalBillableVisits
     ,f.BillingPeriodStartDate
     ,f.BillingPeriodEndDate
     ,f.EpisodeStartDate
     ,f.EpisodeEndDate
     ,f.SOCDate
     ,f.PT
     ,f.OT
     ,f.SN
     ,f.ST
     ,f.MSW
     ,f.HHA
     ,f.TotalCompleted_Closed
     ,f.IsLupaBP
     ,f.PT_Open
     ,f.OT_Open
     ,f.SN_Open
     ,f.ST_Open
     ,f.MSW_Open
     ,f.HHA_Open
     ,f.TotalOpen
     ,f.TotalCompleted_Open
     ,f.IsLupaBP_Open
     ,f.GhostBillingPeriodOpen
     ,f.GhostBillingPeriodClosed

FROM Final f

ORDER BY f.skBillingPeriodStartDateKey DESC
     ,f.EpisodeId ASC
     ,f.BPKey ASC;
   


--The only real change was making PDGM the driver instead of the visit data. In the original, PDGM > TaskDetails > FinalBillingPeriod if TaskDetails didn’t exist, the PDGM row never showed up
--I standardized the BPKey so everything lines up meaning I made sure every part of the query uses the exact same format for the billing-period key
--I switched the joins so Tasks and Requests are optional, so instead of the query requiring visit or request records for a PDGM period to appear, 
	--I changed the logic so PDGM is pulled first and then Tasks and Requests are LEFT JOINed onto it.
--and then I removed filters that were basically blocking PDGM rows unless visits existed like 
			--WHERE td.BillingPeriodStartDate IS NOT NULL
			-- FROM FinalBillingPeriod fb which only included periods wehre TaskDetails existed
--Before, those second periods were getting filtered out because they had no downstream data, now PDGM pulls through regardless, which is why the missing periods are showing up.
--With a LEFT JOIN, if there are no tasks or no requests for that period, the PDGM row still shows up — it just has blanks for those fields.
--Before the change, the joins and filters acted more like INNER JOIN behavior, so a PDGM period only showed up if it had matching visit data. That’s why the second billing periods with no activity weren’t appearing.
--limited data range to alst 13 months
			--	 -- A. Are PDGM periods duplicated inside h?
			--SELECT EpisodeId, BPSeq, COUNT(*) AS c
			--FROM h
			--GROUP BY EpisodeId, BPSeq
			--HAVING COUNT(*) > 1;

			---- B. Which HIPPS join is blowing it up?
			--SELECT COUNT(*) AS base FROM h; -- after you rewrite below, compare counts

			---- C. Compare uniqueness of the driving keys
			--SELECT COUNT(*) total_rows,
			--       COUNT(DISTINCT CAST(EpisodeId AS varchar(20)) + '-' + CAST(BPSeq AS varchar(20))) AS distinct_bpkeys
			--FROM Final_AllPDGM;
