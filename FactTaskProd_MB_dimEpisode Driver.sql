WITH rp
AS (
     SELECT DISTINCT cea.EpiId AS EpisodeId
          ,pp.PpPeriodnumber
          ,pp.PpStartDate
          ,pp.PpEndDate
          ,rp.RpId
          ,rp.RpCode
          ,rp.RpSoeEffectiveFrom
          ,rp.RpSoeEffectiveTo
     
     FROM dbo.ClientEpisodesAll cea
     
     INNER JOIN dbo.ClientEpisodeFs cefs
          ON cea.EpiId = cefs.CefsEpiId
               AND /*cefs.CefsPs = 'P' and*/ cea.SourceSystem = cefs.SourceSystem
     
     INNER JOIN dbo.PdgmPeriod pp
          ON cefs.CefsId = pp.PpCefsId
               AND pp.PpDeleted = 0
               AND cefs.SourceSystem = pp.SourceSystem
     
     INNER JOIN dbo.RatePeriod rp
          ON pp.PpStartDate BETWEEN rp.RpSoeEffectiveFrom
                    AND rp.RpSoeEffectiveTo
               AND rp.RpActive = 'Y'
               AND rp.RpSltId = 1
               AND rp.RpRptId = 5
               AND cea.SourceSystem = rp.SourceSystem
     
     WHERE cea.EpiSlId = 1
     )
     ,pd
AS (
     SELECT t1.EpisodeId
          ,t1.PpPeriodnumber
          ,t1.PpStartDate
          ,t1.PpEndDate
          ,t1.RpId AS RatePeriodId
          ,t1.RpCode
          ,t1.RpSoeEffectiveFrom
          ,t1.RpSoeEffectiveTo
     
     FROM rp t1
     
     INNER JOIN (
          SELECT episodeId
               ,PpPeriodNumber
               ,min(rpsoeeffectivefrom) AS minEffectiveFrom
          
          FROM rp
          
          GROUP BY episodeId
               ,PpPeriodNumber
          ) t2
          ON t1.EpisodeId = t2.EpisodeId
               AND t1.PpPeriodnumber = t2.PpPeriodnumber
               AND t1.RpSoeEffectiveFrom = t2.minEffectiveFrom
     )
     ,
     -- get hipps/HHRG info
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
          ,coalesce(phc.phlupathreshold, phi.phlupathreshold) AS LupaThreshold
          ,
          -- other hipps kp 4/23/2025
          coalesce(phc.phClinicalGrouping, phi.phClinicalGrouping) AS ClinicalGrouping
          ,coalesce(phc.phTiming, phi.phTiming) AS Timing
          ,coalesce(phc.phFunctionalImpairmentLevel, phi.phFunctionalImpairmentLevel) AS FunctionalImpLevel
          ,coalesce(phc.phComorbidityAdjustment, phi.phComorbidityAdjustment) AS ComorbidityAdjustment
          ,coalesce(phc.phCaseMixWeight, phi.phCaseMixWeight) AS CaseMixWeight
          ,cea.EpiId AS episodeId
          ,cefs.CefsPsId AS BPInsuranceId
          ,pp.PpStartDate AS BPStartDate
          ,pp.PpEndDate AS BPEndDate
          ,pp.PpPeriodNumber AS BPSeq
          ,ca.CaId AS AdmissionId
          ,cefs.CefsPsId AS InsuranceId
          ,
          --cefsb.cefsbislupaaddon as isLupa,
          cea.SourceSystem AS SourceSystem
     
     FROM dbo.ClientEpisodesAll cea WITH (NOLOCK)
     
     INNER JOIN dbo.ClientEpisodeFs cefs WITH (NOLOCK)
          ON cea.EpiId = cefs.CefsEpiId
               AND cea.SourceSystem = cefs.SourceSystem
     
     --left join clientEpisodeFSBaseline as cefsb (nolock)
     --on cefs.CefsId=cefsb.cefsbcefsid and cefs.SourceSystem = cefsb.SourceSystem
     INNER JOIN dbo.HCHBPdgmPeriod pp WITH (NOLOCK)
          ON cefs.CefsId = pp.PpCefsId
               AND cefs.SourceSystem = pp.SourceSystem
     
     LEFT JOIN dbo.HCHBClientAdmission ca WITH (NOLOCK)
          ON cea.EpiPaId = ca.CaPaId
               AND cea.EpiSlId = ca.CaSlId
               AND cea.EpiSOCDate = ca.CaSOCDate
               AND cea.SourceSystem = ca.SourceSystem
     
     LEFT JOIN pd AS erp
          ON cea.EpiId = erp.EpisodeId
               AND pp.PpPeriodnumber = erp.PpPeriodnumber
     
     LEFT JOIN dbo.HCHBPdgmHipps phc WITH (NOLOCK)
          ON pp.PpCurrentHipps = phc.Phhipps /*new*/
               AND erp.RatePeriodId = phc.Phrpid
               AND pp.SourceSystem = phc.SourceSystem
     
     LEFT JOIN dbo.HCHBPdgmHipps phi WITH (NOLOCK)
          ON pp.PpInitialHipps = phi.Phhipps /*new*/
               AND erp.RatePeriodId = phi.Phrpid
               AND pp.SourceSystem = phi.SourceSystem
     
     WHERE pp.PpDeleted = 0
          AND cea.EpiStatus NOT IN (
               'DELETED'
               ,'PENDING'
               ,'NON-ADMIT'
               )
          AND cea.EpiSlid = 1
     )
     ,TaskDetails
AS (
     SELECT CONVERT(CHAR(8), /* coalesce( csv.CsvAnticipatedDate, */ csv.CsvSchedDate, 112) AS skScheduleDateKey
          ,--Removed anticipated date, causing issues with visit date accuracy BC 6.26.25
          CSV.CsvId AS ScheduledVisitId
          ,CONVERT(CHAR(8), cev.CevVisitDate, 112) AS skVisitDateKey
          ,cev.CevId AS VisitId
          ,CEA.EpiId AS episodeId
          ,csv.csvLastUpdate AS LastUpdateDate
          ,
          -- Added 7.1.25 BC (Logic to check SOE and EOE to sched visit date)
          MAX(csv.csvLastUpdate) OVER (
               PARTITION BY csv.CsvEpiId
               ,csv.CsvSchedDate
               ,csv.CsvId
               ,sc.scCode
               ) AS MaxUpdateDate
          ,CASE 
               WHEN EBP.BPSeq IS NOT NULL
                    THEN CONVERT(VARCHAR, CEA.epiId) + '-' + CONVERT(VARCHAR, EBP.BPSeq)
               ELSE NULL
               END AS BPKEY
          ,EBP.BPSeq AS BillingPeriodSequence
          ,CONVERT(CHAR(8), EBP.BPStartDate, 112) AS billingPeriodStartDate
          ,CONVERT(CHAR(8), EBP.BPEndDate, 112) AS billingPeriodEndDate
          ,CONVERT(CHAR(8), CEA.EpiStartOfEpisode, 112) AS episodeStartDate
          ,CONVERT(CHAR(8), CEA.EpiEndOfEpisode, 112) AS episodeEndDate
          ,
          --EBP.AdmissionId,
          CONVERT(CHAR(8), CEA.EpiSocDate, 112) AS startOfCareDate
          ,1 AS TaskCount
          ,CASE -- updated 7/11 to exclude missed visits on EOE
               WHEN sc.scCode LIKE '%66%'
                    THEN 0 -- Exclude NVDC codes
               WHEN vs.VsDescription = 'MISSED'
                    AND sc.ScBillable = 'Y'
                    THEN 1
               ELSE 0
               END AS MissedVisit
          ,CASE 
               WHEN vs.VsDescription = 'COMPLETED'
                    AND sc.scCode LIKE '%66%'
                    THEN 1
               ELSE 0
               END AS NVDC
          ,-- non visit discharge metric
          CASE 
               WHEN vs.VsDescription = 'COMPLETED'
                    AND sc.ScVisitType = 'DISCHARGE'
                    THEN 1
               ELSE 0
               END AS DischargeTasks
          ,
          --Added 7.16.25 BC - Added logic to return the completed visit as 1 if there is a completed visit in the visitnumber, otherwise check the lastupdatedate
          CASE 
               WHEN sc.ScBillable = 'Y'
                    THEN CASE 
                              -- 1. If any row is COMPLETED, only that row is flagged
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
                                        -- 2. If no COMPLETED, flag only the single latest row
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
                                        ,sc.ScCode ORDER BY csv.csvLastUpdate DESC
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
          CASE 
               WHEN vs.VsDescription = 'COMPLETED'
                    THEN 1
               WHEN csv.CsvSchedDate >= cea.EpiStartOfEpisode
                    AND csv.CsvSchedDate <= cea.EpiEndOfEpisode
                    THEN 1
               ELSE 0
               END AS VisitBetweenSOEandEOE
          ,CASE 
               WHEN vs.VsDescription = 'COMPLETED'
                    AND sc.scCode NOT LIKE '%66%'
                    AND CEV.CevBillable = 1
                    THEN 1 --completed visits only count if billable per KR
               ELSE 0
               END AS CompletedVisits
          ,-- completed visits, not counting NVDC
          CASE 
               WHEN CEV.CevBillable = 1
                    THEN 1
               ELSE 0
               END AS VisitBillable
          ,CASE 
               WHEN sc.scBillable = 'Y'
                    THEN 1
               ELSE 0
               END AS ServiceBillable
          ,CASE 
               WHEN SC.ScPayable = 'Y'
                    THEN 1
               ELSE 0
               END AS Payable
          ,CASE -- Logic added 6.27.25 BC / This is to flag OPEN and CLOSED for the open/closed metrics.
               WHEN CEA.EpiEndOfEpisode <= CAST(GETDATE() - 1 AS DATE)
                    THEN 'Closed' -- BC-There may need to be logic adjustments depending on if we go based on status, or both status and dates		
               ELSE 'Open'
               END AS OpenClosedFlag
          ,SC.ScDesc AS TaskDesc
          ,SC.ScVisitType AS TaskType
          ,sc.scCode AS TaskCode
          ,SC.ScJdCode AS TaskJobCode
          ,D.DscDesc AS Discipline
          ,sc.ScProductivityPoints AS ProductivityPts
          ,vs.VsDescription AS TaskStatus
          ,vmr.VmDesc AS VisitMissedReason
          ,--new 20230215 WLF
          P.PatientId AS PatientId
          ,CEFS.CefsPsid AS InsuranceId
          ,--select * from dimInsurance where insuranceid=28534
          i.InsuranceTypeId AS InsuranceTypeId
          ,i.InsuranceType
          ,EpiBranchcode AS BranchCode
          ,B.Id AS skOrgKey
          ,right(B.ForeignCode, 5) AS [Location]
          ,cea.EpiSlId
          ,
          --	hcpcs.BcHCPCS as HCPCS,
          EBP.HIPPS
          ,EBP.LupaThreshold
          ,
          --h.isLupa,
          EBP.ClinicalGrouping
          ,EBP.Timing
          ,EBP.FunctionalImpLevel
          ,EBP.ComorbidityAdjustment
          ,EBP.CaseMixWeight
          ,csv.SourceSystem
          ,cev.CevDeleted
          ,cea.epiStatus
          ,csv.CsvVisitNumber
          ,cea.EpiLastName
          ,cea.EpiFirstName
          ,cea.EpiMI
          ,CEA.EpiMrNum as MRN

          -- BC - Added 7.18.25 for validation to HCHB
          ,CONCAT_WS(' ', CONCAT (
                    cea.EpiLastName
                    ,', '
                    ,cea.EpiFirstName
                    ), cea.EpiMI) AS PatientName
          ,CONCAT_WS(' ', CONCAT (
                    DW.WorkerLastName
                    ,', '
                    ,DW.WorkerFirstName
                    ), DW.WorkerMiddleInitial) AS WorkerName
          ,dw.WorkerId
          ,dw.JobTitle
          ,dw.JobDescriptionCode
          ,dw.WorkerHomeBranch
     
     FROM dbo.ClientSchedVisits CSV WITH (NOLOCK) -- cant use vw_dimClientEpisodeVisitWithWorkerId because it doesnt have prod points (or a way to join to service codes)
     
     INNER JOIN dbo.VisitStatuses VS WITH (NOLOCK)
          ON CSV.CsvStatus = VS.vsStatus
               AND csv.SourceSystem = vs.SourceSystem
     
     /** need join to task status table **/
     INNER JOIN dbo.ServiceCodes SC WITH (NOLOCK)
          ON CSV.CsvScid = SC.scid
               AND csv.SourceSystem = sc.SourceSystem
     
     INNER JOIN dbo.Disciplines D WITH (NOLOCK)
          ON SC.ScDiscipline = D.DscCode
               AND sc.SourceSystem = d.SourceSystem
     
     INNER JOIN dbo.ClientEpisodesAll CEA WITH (NOLOCK)
          ON CSV.CsvEpiId = CEA.EpiId
               AND csv.SourceSystem = cea.SourceSystem
     
     INNER JOIN dbo.dimBranch B WITH (NOLOCK)
          ON CEA.EpiBranchcode = B.BranchCode
               AND cea.SourceSystem = b.SourceSystem
     
     INNER JOIN dbo.dimPatient P WITH (NOLOCK)
          ON CEA.EpiPaId = P.PatientId
               AND cea.SourceSystem = p.SourceSystem
     
     LEFT JOIN h AS EBP
          ON CEA.epiId = EBP.episodeId
               AND CEA.SourceSystem = EBP.SourceSystem
               AND csv.CsvSchedDate BETWEEN EBP.BPStartDate
                    AND EBP.BPEndDate
     
     LEFT JOIN dbo.ClientEpisodeVisitsAll CEV WITH (NOLOCK)
          ON CSV.CsvId = CEV.CevCsvId
               AND csv.SourceSystem = cev.SourceSystem
               AND cev.CevDeleted = 0
     
     LEFT JOIN dbo.ClientEpisodeFs CEFS WITH (NOLOCK)
          ON cea.epiid = cefs.CefsEpiId
               AND cefs.CefsPs = 'P'
               AND cefs.CefsActive = 'Y'
               AND cea.SourceSystem = cefs.SourceSystem
     
     --left join HCPHCSQuery hcpcs (nolock)
     --on CSV.CsvId = hcpcs.CsvId and CSV.SourceSystem = hcpcs.SourceSystem
     LEFT JOIN dbo.VisitMissedReasons vmr WITH (NOLOCK)
          ON CSV.CsvVmId = vmr.VmId
               AND CSV.SourceSystem = VMR.SourceSystem
     
     LEFT JOIN diminsurance i(NOLOCK)
          ON CEFS.CefsPsid = i.InsuranceId
               AND cefs.SourceSystem = i.SourceSystem
     
     LEFT JOIN dbo.dimWorker dw WITH (NOLOCK)
          ON CEV.CevAgId = dw.WorkerId
               AND dw.SourceSystem = CEV.SourceSystem
     
     WHERE csv.CsvSchedDate BETWEEN DATEADD(M, - 13, DATEADD(M, DATEDIFF(M, 0, GETDATE()), 0))
               AND GETDATE() + 60
          AND cea.EpiSlId = 1
          --and csv.SourceSystem = 'Abode'
          AND cea.EpiStatus NOT IN (
               'DELETED'
               ,'PENDING'
               ,'NON-ADMIT'
               )
          --and SC.ScVisitType not in ('Medical Treatment', 'Phone Visit') 
          --and sc.scCode not like '%11N%'
          --and sc.scCode not like '%10N%'
          --and sc.scCode not like '%44%'
          --and csv.CsvStatus <> 'P'
          --and sc.scBillable ='Y'
          --and CASE WHEN ScVisitType='DISCHARGE' THEN 'N' 
          --	WHEN ScVisitType='MEDICAL TREATMENT' THEN 'Y'
          --	WHEN ScDesc like '%NO VISIT%' THEN 'Y'
          --	WHEN ScDesc like '%DEATH AT HOME%' THEN 'Y'
          --	WHEN ScDesc like '%REMOTE VISIT%' THEN 'Y'
          --	ELSE 'N' END ='N' -- exclude y/n
          --   and vs.VsDescription <> 'OFFICE REASSIGNED'
          --and (vmr.VmDesc <>'DUPLICATE VISIT' or vmr.VmDesc is null)
          --and (vmr.VmDesc <>'INCORRECT SERVICE CODE' or vmr.VmDesc is null) -- new to not count duplicate visits kp 
		 
          AND (
               CEV.CevDeleted <> 1
               OR CEV.CevDeleted IS NULL
               ) -- exclude deleted records where status is completed
     )

SELECT DISTINCT skVisitDateKey
     ,VisitId
     ,skScheduleDateKey
     ,LastUpdateDate
     ,ScheduledVisitId
     ,
     --AdmissionId,
     episodeId
     ,PatientName
	 ,MRN
     ,bpKey
     ,billingPeriodStartDate AS skbillingPeriodStartDateKey
     ,billingPeriodEndDate AS skbillingPeriodEndDateKey
     ,BillingPeriodSequence
     ,episodeStartDate AS skepisodeStartDateKey
     ,episodeEndDate AS skepisodeEndDateKey
     ,startOfCareDate AS skstartOfCareDateKey
     ,CompletedVisits
     ,InHomeVisits_VisitNumber
     ,taskCount
     ,MissedVisit
     ,NVDC
     ,DischargeTasks
     ,Visitbillable
     ,ServiceBillable
     ,payable
     ,OpenClosedFlag
     ,VisitBetweenSOEandEOE
     ,WorkerId
     ,WorkerName
     ,JobTitle
     ,JobDescriptionCode
     ,WorkerHomeBranch
     ,taskDesc
     ,taskType
     ,taskCode
     ,CsvVisitNumber AS VisitNumber
     ,taskJobCode
     ,Discipline AS taskDiscipline
     ,taskStatus
     ,VisitMissedReason
     ,PatientId
     ,InsuranceId
     ,InsuranceTypeId
     ,InsuranceType
     ,BranchCode
     ,skOrgKey
     ,[Location]
     ,EpiSlId AS ServiceLineId
     ,
     --HCPCS,
     HIPPS
     ,LupaThreshold
     ,ClinicalGrouping
     ,Timing
     ,FunctionalImpLevel
     ,ComorbidityAdjustment
     ,CaseMixWeight
     ,SourceSystem
     ,CevDeleted
     ,epistatus


FROM TaskDetails


	 --WHERE  taskJobCode NOT in ('MSW','RN','LPN','SN','PT','PTA','OT','ST','COTA','AIDE')
	 --AND episodeStartDate BETWEEN '20251011' AND '20251201'
	 --AND OpenClosedFlag = 'Open'