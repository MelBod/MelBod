WITH
     -- 1) Rate period lookup by episode -> period -> rate period
rp
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
               AND rp.RpSltId = 1 --Home Health Service Line Type
               AND rp.RpRptId = 5 --Rate Period Type
               AND cea.SourceSystem = rp.SourceSystem
     
     WHERE cea.EpiSlId = 1 --Home Health Service Line
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
     -- 3) HIPPS / LUPA mapping per PDGM Period
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
               ELSE NULL
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
                    ELSE NULL
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
     -- 6) TaskDetails
TaskDetails
AS (
     SELECT csv.CsvId AS ScheduledVisitId
          ,cev.CevId AS VisitId
          ,cea.EpiId AS EpisodeId
          ,csv.CsvLastUpdate AS LastUpdateDate
          ,
          -- Added 7.1.25 BC (Logic to check SOE and EOE to sched visit date)
          MAX(csv.CsvLastUpdate) OVER (
               PARTITION BY csv.CsvEpiId
               ,csv.CsvSchedDate
               ,csv.CsvId
               ,sc.ScCode
               ) AS MaxUpdateDate
          ,CASE 
               WHEN EBP.BPSeq IS NOT NULL
                    THEN CAST(cea.EpiId AS VARCHAR(20)) + '-' + CAST(EBP.BPSeq AS VARCHAR(20))
               ELSE NULL
               END AS BPKey
          ,EBP.BPSeq AS BillingPeriodSequence
          ,CONVERT(CHAR(8), EBP.BPStartDate, 112) AS BillingPeriodStartDate
          ,CONVERT(CHAR(8), EBP.BPEndDate, 112) AS BillingPeriodEndDate
          ,CONVERT(CHAR(8), CEA.EpiStartOfEpisode, 112) AS EpisodeStartDate
          ,CONVERT(CHAR(8), CEA.EpiEndOfEpisode, 112) AS EpisodeEndDate
          ,CONVERT(CHAR(8), CEA.EpiSocDate, 112) AS StartOfCareDate
          ,1 AS TaskCount
          ,
          --Added 7.16.25 BC - Added logic to return the completed visit as 1 if there is a completed visit in the visitnumber, otherwise check the lastupdatedate
          -- a) In-home visit logic
          -- If any row is COMPLETED, only that row is flagged
		  -- For each billable visit number, count exactly one row: the completed one if it exists otherwise the most recent scheduled or missed PRN visit — so that each visit number contributes at most one valid ‘in-home’ visit.
          CASE 
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
                                        -- If no COMPLETED, flag only the single latest row
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
          ,
          -- Added 7.2.25 BC (Logic to check if a scheduled visit is happening within the SOE and EOE dates)
          -- b) Scheduled visits new (added CHECKED OUT) 
          --Including CHECKED OUT ensures a visit within the episode window that hasn’t been posted as completed still gets recognized as a valid scheduled visit for that episode.
          CASE 
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
          ,
          -- c) Visit flags
          CASE 
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
          ,-- completed visits, not counting NVDC
          CASE 
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
          ,
          -- Logic added 6.27.25 BC / This is to flag OPEN and CLOSED for the open/closed metrics.
          CASE 
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
          ,--select * from dimInsurance where insuranceid=28534 BC
          i.InsuranceTypeId
          ,i.InsuranceType
          ,cea.EpiBranchcode AS BranchCode
          ,b.Id AS skOrgKey
          ,RIGHT(b.ForeignCode, 5) AS [Location]
          ,cea.EpiSlId
          ,EBP.HIPPS
          --Update to Threshold logic specifically for UHC is always 4 visits
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
          ,
          -- BC - Added 7.18.25 for validation to HCHB
          csv.SourceSystem
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
     
     FROM dbo.ClientSchedVisits AS csv WITH (NOLOCK) -- cant use vw_dimClientEpisodeVisitWithWorkerId because it doesnt have prod points (or a way to join to service codes)
     
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
FinalBillingPeriod
AS (
     SELECT td.EpisodeId
          ,td.BPKey
          ,td.BillingPeriodStartDate AS skBillingPeriodStartDateKey
          ,td.BillingPeriodEndDate AS skBillingPeriodEndDateKey
          ,td.EpisodeStartDate AS skEpisodeStartDateKey
          ,td.EpisodeEndDate AS skEpisodeEndDateKey
          ,td.StartOfCareDate AS skStartOfCareKey
          ,td.BillingPeriodSequence
          ,td.PatientId
		  ,CAST(td.PatientId AS VARCHAR(50)) + '_' + td.SourceSystem AS PatientSystemId
          ,td.PatientName
          ,td.PatientAddress
          ,td.InsuranceId
          ,td.InsuranceTypeId
          ,td.InsuranceType
          ,td.BranchCode
          ,td.[Location]
          ,td.HIPPS
         
          ,MAX(td.LupaThreshold) AS LupaThreshold
          ,MAX(td.ClinicalGrouping) AS ClinicalGrouping
          ,MAX(td.Timing) AS Timing
          ,MAX(td.FunctionalImpLevel) AS FunctionalImpLevel
          ,MAX(td.ComorbidityAdjustment) AS ComorbidityAdjustment
          ,MAX(td.CaseMixWeight) AS CaseMixWeight
          ,MAX(td.BP_OpenClosedFlag) AS BP_OpenClosedFlag
          ,MAX(td.EpiStatus) AS EpiStatus
          ,
          -- a) Visits and counts
          SUM(COALESCE(td.ScheduledVisits, 0)) AS ScheduledVisits
          ,sum(CASE -- updated 7/11 to exclude missed visits on EOE
                    WHEN td.TaskCode LIKE '%66%'
                         THEN 0 -- Exclude NVDC codes
                    WHEN td.TaskStatus = 'MISSED'
                         AND td.ServiceBillable = '1'
                         THEN 1
                    ELSE 0
                    END) AS MissedVisits
          ,SUM(CASE 
                    WHEN td.VisitBillable = 1
                         THEN 1
                    ELSE 0
                    END) AS TotalBillableVisits
          ,
          --SUM(CASE WHEN td.TaskStatus = 'MISSED' THEN 1 ELSE 0 END) AS MissedVisits,
          -- b) Completed by period type
          SUM(CASE 
                    WHEN td.BP_OpenClosedFlag = 'Open'
                         THEN td.CompletedVisits
                    ELSE 0
                    END) AS TotalCompleted_Open
          ,
          -- c) Completed (Closed) by discipline
          SUM(CASE 
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
          ,
          -- d) LUPA (Closed)
          CASE 
               WHEN SUM(td.CompletedVisits) > 0
                    AND SUM(td.CompletedVisits) < MAX(td.LupaThreshold)
                    AND MAX(td.BP_OpenClosedFlag) = 'Closed'
                    THEN 1
               ELSE 0
               END AS IsLupaBP
          -- e) Open (in-home) rollups
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
          ,
          -- f) LUPA (Open)
          CASE 
               WHEN SUM(td.InHomeVisits_VisitNumber) > 0
                    AND SUM(td.InHomeVisits_VisitNumber) < MAX(td.LupaThreshold)
                    AND MAX(td.BP_OpenClosedFlag) = 'Open'
                    THEN 1
               ELSE 0
               END AS IsLupaBP_Open
          ,
          -- g) Has billable service
          CASE 
               WHEN SUM(td.ServiceBillable) > 0
                    THEN 'Y'
               ELSE 'N'
               END AS HasBillableService
           --h) Ghost flags
          ,CASE 
               WHEN SUM(td.CompletedVisits) = 0
                    AND MAX(td.BP_OpenClosedFlag) = 'Closed'
                    THEN 1
               ELSE 0
               END AS BP0VisitCount_Closed
          ,CASE 
               WHEN SUM(td.InHomeVisits_VisitNumber) = 0
                    AND MAX(td.BP_OpenClosedFlag) = 'Open'
                    THEN 1
               ELSE 0
               END AS BP0VisitCount_Open
          ,CASE 
               WHEN MAX(td.BP_OpenClosedFlag) = 'Open'
                    AND SUM(CASE 
                              WHEN td.TaskStatus IN (
                                        'Missed'
                                        ,'Rescheduled'
                                        ,'Office Reassigned'
                                        ,'Declined'
                                        ,'Requested'
                                        )
                                   OR td.InHomeVisits_VisitNumber = 1
                                   THEN 1
                              ELSE 0
                              END) > 0
                    AND SUM(CASE 
                              WHEN td.CompletedVisits = 1
                                   AND td.ServiceBillable = 1
                                   THEN 1
                              ELSE 0
                              END) = 0
                    THEN 1
               ELSE 0
               END AS GhostBillingPeriodOpen
          --,CASE 
          --     WHEN MAX(td.BP_OpenClosedFlag) = 'Open'
          --          AND (
          --               -- A) No completed visits at all
          --               SUM(td.CompletedVisits) = 0
          --               OR
          --               -- B) Some visits exist but none are billable completions
          --               (
          --                    SUM(td.CompletedVisits) > 0
          --                    AND SUM(CASE 
          --                              WHEN td.CompletedVisits = 1
          --                                   AND td.ServiceBillable = 1
          --                                   THEN 1
          --                              ELSE 0
          --                              END) = 0
          --                    )
          --               OR
          --               -- C) Any visit with one of these task statuses
          --               SUM(CASE 
          --                         WHEN td.TaskStatus IN (
          --                                   'Missed'
          --                                   ,'Rescheduled'
          --                                   ,'Office Reassigned'
          --                                   ,'Declined'
          --                                   ,'Requested'
          --                                   )
          --                              THEN 1
          --                         ELSE 0
          --                         END) > 0
          --               )
          --          THEN 1
          --     ELSE 0
          --     END AS GhostBillingPeriodOpenRev(MB)
          ,CASE 
    WHEN SUM(CASE 
                WHEN td.CompletedVisits = 1 THEN 1 
                ELSE 0 
             END) > 0
         THEN 0
    ELSE 1
END AS GhostBillingPeriodClosed

     FROM TaskDetails AS td
     
     WHERE td.InsuranceType IN (
               'COMMERCIAL INSURANCE-EPISODIC'
               ,'MEDICARE'
               ,'MEDICARE REPLACEMENT - EPISODIC'
               ,'COMMERCIAL INSURANCE-EPISODIC/CASE RATE'
               )
          AND td.BillingPeriodStartDate IS NOT NULL
          --AND EpisodeId = 931908

          --AND BillingPeriodSequence = 2
          --AND VisitBillable = 0
          --AND HIPPS IS NOT NULL
          --AND BillingPeriodStartDate BETWEEN '20250918' AND '20251027'
          --AND BP_OpenClosedFlag = 'Open'
		 
     GROUP BY td.EpisodeId
          ,td.BPKey
          ,td.BillingPeriodStartDate
          ,td.BillingPeriodEndDate
          ,td.BillingPeriodSequence
          ,td.EpisodeStartDate
          ,td.EpisodeEndDate
          ,td.StartOfCareDate
          ,td.PatientId
		 ,td.SourceSystem
          ,td.PatientName
          ,td.PatientAddress
          ,td.InsuranceId
          ,td.InsuranceTypeId
          ,td.InsuranceType
          ,td.BranchCode
          ,td.[Location]
          ,td.HIPPS
          --, td.TaskCode, td.TaskStatus, td.ServiceBillable
     )

--8) Join FinalBillingPeriod with BP Requests Summary
SELECT fb.EpisodeId
     ,fb.BPKey
     ,fb.skBillingPeriodStartDateKey
     ,fb.skBillingPeriodEndDateKey
     ,fb.skEpisodeStartDateKey
     ,fb.skEpisodeEndDateKey
     ,fb.skStartOfCareKey
     ,fb.BillingPeriodSequence
     ,fb.PatientId
     ,fb.PatientName
	  ,fb.PatientSystemId
     ,fb.PatientAddress
     ,fb.InsuranceId
     ,fb.InsuranceTypeId
     ,fb.InsuranceType
     ,fb.BranchCode
     ,fb.[Location]
     ,fb.HIPPS
     ,fb.LupaThreshold
     ,fb.ClinicalGrouping
     ,fb.Timing
     ,fb.FunctionalImpLevel
     ,fb.ComorbidityAdjustment
     ,fb.CaseMixWeight
     ,fb.BP_OpenClosedFlag
     ,fb.EpiStatus
     ,COALESCE(brs.Requests, 0) AS Requests
     ,fb.MissedVisits
     ,fb.ScheduledVisits
     ,fb.HasBillableService
     ,fb.TotalBillableVisits
     -- a) Formatted date strings
     ,FORMAT(CONVERT(DATE, fb.skBillingPeriodStartDateKey, 112), 'M/dd/yyyy') AS BillingPeriodStartDate
     ,FORMAT(CONVERT(DATE, fb.skBillingPeriodEndDateKey, 112), 'M/dd/yyyy') AS BillingPeriodEndDate
     ,FORMAT(CONVERT(DATE, fb.skEpisodeStartDateKey, 112), 'M/dd/yyyy') AS EpisodeStartDate
     ,FORMAT(CONVERT(DATE, fb.skEpisodeEndDateKey, 112), 'M/dd/yyyy') AS EpisodeEndDate
     ,FORMAT(CONVERT(DATE, fb.skStartOfCareKey, 112), 'M/dd/yyyy') AS SOCDate
     ,fb.BranchCode + '000' + CAST(fb.PatientId AS VARCHAR(20)) + '0' + CAST(1 AS VARCHAR(1)) AS MRN
     -- b) Closed totals
     ,fb.PT
     ,fb.OT
     ,fb.SN
     ,fb.ST
     ,fb.MSW
     ,fb.HHA
     ,fb.TotalCompleted_Closed
     ,fb.IsLupaBP
     -- c) Open totals
     ,fb.PT_Open
     ,fb.OT_Open
     ,fb.SN_Open
     ,fb.ST_Open
     ,fb.MSW_Open
     ,fb.HHA_Open
     ,fb.TotalOpen
     ,fb.TotalCompleted_Open
     ,fb.IsLupaBP_Open
     -- d) Ghost flags
     ,fb.GhostBillingPeriodOpen
     ,fb.GhostBillingPeriodClosed

FROM FinalBillingPeriod AS fb

LEFT JOIN BP_Requests_Summary AS brs
     ON fb.BPKey = brs.BPKey

ORDER BY skBillingPeriodStartDateKey DESC
     ,EpisodeId ASC
     ,fb.BPKey ASC;
     -- 9) Final Select: Simplified Output
     --  SELECT
     --      fb.EpisodeId,
     --      fb.BPKey,
     --      -- Billing Period Dates
     --      FORMAT(CONVERT(DATE, fb.skBillingPeriodStartDateKey, 112), 'M/dd/yyyy') AS BillingPeriodStartDate,
     --      FORMAT(CONVERT(DATE, fb.skBillingPeriodEndDateKey, 112), 'M/dd/yyyy') AS BillingPeriodEndDate,
     --      -- Episode Dates
     --      FORMAT(CONVERT(DATE, fb.skEpisodeStartDateKey, 112), 'M/dd/yyyy') AS EpisodeStartDate,
     --      FORMAT(CONVERT(DATE, fb.skEpisodeEndDateKey, 112), 'M/dd/yyyy') AS EpisodeEndDate,
     --      -- Metrics
     --      fb.LupaThreshold,
     --      COALESCE(brs.Requests, 0) AS Requests,
     --      fb.MissedVisits,
     --      fb.ScheduledVisits,
     --fb.TotalCompleted_Closed,
     --      fb.TotalCompleted_Open,
     --      fb.TotalOpen,
     --      fb.IsLupaBP_Open,
     --      fb.GhostBillingPeriodOpen
     --  FROM FinalBillingPeriod AS fb
     --  LEFT JOIN BP_Requests_Summary AS brs
     --      ON fb.BPKey = brs.BPKey
     --  ORDER BY fb.BPKey DESC;
