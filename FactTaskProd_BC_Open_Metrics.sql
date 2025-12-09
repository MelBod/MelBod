with
rp as
(select
		distinct
		cea.EpiId as EpisodeId,
		pp.PpPeriodnumber,
		pp.PpStartDate,
		pp.PpEndDate,
		rp.RpId,
		rp.RpCode,
		rp.RpSoeEffectiveFrom,
		rp.RpSoeEffectiveTo
	from
		dbo.ClientEpisodesAll cea
		inner join
		dbo.ClientEpisodeFs cefs
		on cea.EpiId = cefs.CefsEpiId and /*cefs.CefsPs = 'P' and*/ cea.SourceSystem = cefs.SourceSystem
		inner join
		dbo.PdgmPeriod pp
		on cefs.CefsId = pp.PpCefsId and pp.PpDeleted = 0 and cefs.SourceSystem=pp.SourceSystem
		inner join
		dbo.RatePeriod rp
		on pp.PpStartDate between rp.RpSoeEffectiveFrom and rp.RpSoeEffectiveTo
			and rp.RpActive = 'Y' and rp.RpSltId = 1 and rp.RpRptId = 5 and cea.SourceSystem = rp.SourceSystem
	where
		cea.EpiSlId = 1
		),
pd as
(
		select 
	t1.EpisodeId,
	t1.PpPeriodnumber,
	t1.PpStartDate,
	t1.PpEndDate,
	t1.RpId as RatePeriodId,
	t1.RpCode,
	t1.RpSoeEffectiveFrom,
	t1.RpSoeEffectiveTo
from 
	rp t1
	inner join 
	(select episodeId, PpPeriodNumber, min(rpsoeeffectivefrom) as minEffectiveFrom 
	from rp group by episodeId, PpPeriodNumber) t2
	on t1.EpisodeId = t2.EpisodeId and t1.PpPeriodnumber = t2.PpPeriodnumber and t1.RpSoeEffectiveFrom = t2.minEffectiveFrom

),

-- get hipps/HHRG info
h as 
(

	select distinct
		pp.PpId as PPId,
		case
			when pp.PpCurrentHipps <> '' then pp.PpCurrentHipps
			when pp.PpInitialHipps <> '' then pp.PpInitialHipps
			else null
		end as HIPPS,
		coalesce(phc.phlupathreshold, phi.phlupathreshold) as LupaThreshold,
		-- other hipps kp 4/23/2025
		coalesce(phc.phClinicalGrouping, phi.phClinicalGrouping) as ClinicalGrouping,
		coalesce(phc.phTiming, phi.phTiming) as Timing,
		coalesce(phc.phFunctionalImpairmentLevel, phi.phFunctionalImpairmentLevel) as FunctionalImpLevel,
		coalesce(phc.phComorbidityAdjustment, phi.phComorbidityAdjustment) as ComorbidityAdjustment,
		coalesce(phc.phCaseMixWeight, phi.phCaseMixWeight) as CaseMixWeight,
		cea.EpiId as episodeId,
		cefs.CefsPsId as BPInsuranceId,
		pp.PpStartDate as BPStartDate,
		pp.PpEndDate as BPEndDate,
		pp.PpPeriodNumber as BPSeq,
		ca.CaId as AdmissionId,
		cefs.CefsPsId as InsuranceId,
		--cefsb.cefsbislupaaddon as isLupa,
		cea.SourceSystem as SourceSystem
	from
		dbo.ClientEpisodesAll cea with (nolock)
		inner join
		dbo.ClientEpisodeFs cefs with (nolock)
		on cea.EpiId = cefs.CefsEpiId and cea.SourceSystem = cefs.SourceSystem
		--left join clientEpisodeFSBaseline as cefsb (nolock)
		--on cefs.CefsId=cefsb.cefsbcefsid and cefs.SourceSystem = cefsb.SourceSystem
		inner join
		dbo.HCHBPdgmPeriod pp with (nolock)
		on cefs.CefsId = pp.PpCefsId and cefs.SourceSystem = pp.SourceSystem
		left join
		dbo.HCHBClientAdmission ca with (nolock)
		on cea.EpiPaId = ca.CaPaId and cea.EpiSlId = ca.CaSlId and cea.EpiSOCDate = ca.CaSOCDate and cea.SourceSystem = ca.SourceSystem
		left join
		pd as erp
		on cea.EpiId = erp.EpisodeId and pp.PpPeriodnumber = erp.PpPeriodnumber
		left join
		dbo.HCHBPdgmHipps phc with (nolock)
		on pp.PpCurrentHipps = phc.Phhipps /*new*/ and erp.RatePeriodId = phc.Phrpid 
		and pp.SourceSystem = phc.SourceSystem
		left join
		dbo.HCHBPdgmHipps phi with (nolock)
		on pp.PpInitialHipps = phi.Phhipps /*new*/ and erp.RatePeriodId = phi.Phrpid 
		and pp.SourceSystem = phi.SourceSystem
	where
		pp.PpDeleted = 0
		and cea.EpiStatus not in ('DELETED', 'PENDING','NON-ADMIT')
		and cea.EpiSlid = 1
		),

TaskDetails as
(
select
	CONVERT(CHAR(8),/* coalesce( csv.CsvAnticipatedDate, */ csv.CsvSchedDate,112) as skScheduleDateKey, --Removed anticipated date, causing issues with visit date accuracy BC 6.26.25
	CSV.CsvId as ScheduledVisitId,
	CONVERT(CHAR(8),cev.CevVisitDate,112) as skVisitDateKey,
	cev.CevId as VisitId,	
	CEA.EpiId as episodeId,
	csv.csvLastUpdate as LastUpdateDate,
-- Added 7.1.25 BC (Logic to check SOE and EOE to sched visit date)
	MAX(csv.csvLastUpdate) OVER (
    PARTITION BY csv.CsvEpiId, csv.CsvSchedDate, csv.CsvId, sc.scCode
) AS MaxUpdateDate,
	CASE 
		WHEN EBP.BPSeq IS NOT NULL THEN CONVERT(VARCHAR,CEA.epiId)+ '-'+ CONVERT(VARCHAR,EBP.BPSeq)
		ELSE NULL 
	END AS BPKEY,
	EBP.BPSeq as BillingPeriodSequence,
	CONVERT(CHAR(8),EBP.BPStartDate, 112) as billingPeriodStartDate,
	CONVERT(CHAR(8),EBP.BPEndDate, 112) as billingPeriodEndDate,	
	CONVERT(CHAR(8), CEA.EpiStartOfEpisode, 112) as episodeStartDate,
	CONVERT(CHAR(8), CEA.EpiEndOfEpisode, 112) as episodeEndDate,
	--EBP.AdmissionId,
	CONVERT(CHAR(8), CEA.EpiSocDate, 112) as startOfCareDate,
1 AS  TaskCount,

CASE -- updated 7/11 to exclude missed visits on EOE
    WHEN sc.scCode LIKE '%66%' THEN 0 -- Exclude NVDC codes
    WHEN vs.VsDescription = 'MISSED'
         AND sc.ScBillable = 'Y'
    THEN 1
    ELSE 0
END AS MissedVisit,
CASE 
		WHEN  vs.VsDescription='COMPLETED' AND sc.scCode LIKE '%66%'  THEN 1 
		ELSE 0 
		END AS NVDC,-- non visit discharge metric
	CASE 
		WHEN vs.VsDescription ='COMPLETED'  AND sc.ScVisitType='DISCHARGE' THEN 1		
        ELSE 0
		END AS DischargeTasks,

--Added 7.16.25 BC - Added logic to return the completed visit as 1 if there is a completed visit in the visitnumber, otherwise check the lastupdatedate

CASE 
    WHEN sc.ScBillable = 'Y' THEN
        CASE 
            -- 1. If any row is COMPLETED, only that row is flagged
            WHEN 
                MAX(CASE WHEN vs.VsDescription = 'COMPLETED' THEN 1 ELSE 0 END)
                OVER (PARTITION BY csv.CsvEpiId, csv.CsvVisitNumber, csv.CsvScId, sc.ScCode) = 1
                AND vs.VsDescription = 'COMPLETED'
            THEN 
                CASE 
                    WHEN sc.ScCode LIKE '%PRN%' THEN 
                        CASE WHEN vs.VsDescription IN ('COMPLETED', 'MISSED') THEN 1 ELSE 0 END
                    ELSE 1 
                END

            -- 2. If no COMPLETED, flag only the single latest row
            WHEN 
                MAX(CASE WHEN vs.VsDescription = 'COMPLETED' THEN 1 ELSE 0 END)
                OVER (PARTITION BY csv.CsvEpiId, csv.CsvVisitNumber, csv.CsvScId, sc.ScCode) = 0
                AND ROW_NUMBER() OVER (
                    PARTITION BY csv.CsvEpiId, csv.CsvVisitNumber, csv.CsvScId, sc.ScCode
                    ORDER BY csv.csvLastUpdate DESC, csv.CsvSchedDate DESC
                ) = 1
                AND (
                    sc.ScCode NOT LIKE '%PRN%' OR 
                    (sc.ScCode LIKE '%PRN%' AND vs.VsDescription IN ('COMPLETED', 'MISSED'))
                )
            THEN 
                CASE 
                    WHEN sc.ScCode LIKE '%PRN%' THEN 
                        CASE WHEN vs.VsDescription IN ('COMPLETED', 'MISSED') THEN 1 ELSE 0 END
                    ELSE 1 
                END

            ELSE 0
        END
    ELSE 0
END AS InHomeVisits_VisitNumber,


-- Added 7.2.25 BC (Logic to check if a scheduled visit is happening within the SOE and EOE dates)
CASE
    WHEN vs.VsDescription = 'COMPLETED' THEN 1
    WHEN csv.CsvSchedDate >= cea.EpiStartOfEpisode
         AND csv.CsvSchedDate <= cea.EpiEndOfEpisode THEN 1
    ELSE 0
END AS VisitBetweenSOEandEOE,
	CASE 
		WHEN vs.VsDescription='COMPLETED' AND sc.scCode not LIKE '%66%' and  CEV.CevBillable=1  THEN 1		--completed visits only count if billable per KR
        ELSE 0
		END AS CompletedVisits,-- completed visits, not counting NVDC
	CASE 
		WHEN CEV.CevBillable = 1 THEN 1 
		ELSE 0 
	END AS VisitBillable,
	CASE 
		WHEN sc.scBillable = 'Y' THEN 1 
		ELSE 0 
	END AS ServiceBillable,
	CASE 
		WHEN SC.ScPayable = 'Y' THEN 1 
		ELSE 0 
	END AS Payable,
	CASE -- Logic added 6.27.25 BC / This is to flag OPEN and CLOSED for the open/closed metrics.
		WHEN CEA.EpiEndOfEpisode <= CAST(GETDATE() -1 AS DATE) THEN 'Closed' -- BC-There may need to be logic adjustments depending on if we go based on status, or both status and dates		
		ELSE 'Open'
	END AS OpenClosedFlag,
	
	SC.ScDesc as TaskDesc,
	SC.ScVisitType as TaskType,
	sc.scCode as TaskCode,
	SC.ScJdCode as TaskJobCode,
	D.DscDesc as Discipline,
	sc.ScProductivityPoints as ProductivityPts,
	vs.VsDescription as TaskStatus,
	vmr.VmDesc AS VisitMissedReason, --new 20230215 WLF
	P.PatientId as PatientId,
	CEFS.CefsPsid as InsuranceId, --select * from dimInsurance where insuranceid=28534
	i.InsuranceTypeId as InsuranceTypeId, 
	i.InsuranceType,
	EpiBranchcode as BranchCode,
	B.Id as skOrgKey,
	right(B.ForeignCode, 5) as [Location],
	cea.EpiSlId,
--	hcpcs.BcHCPCS as HCPCS,
	EBP.HIPPS,
	EBP.LupaThreshold,
	--h.isLupa,
    EBP.ClinicalGrouping,
	EBP.Timing,
	EBP.FunctionalImpLevel,
	EBP.ComorbidityAdjustment,
	EBP.CaseMixWeight,		
	csv.SourceSystem, cev.CevDeleted, cea.epiStatus, csv.CsvVisitNumber, cea.EpiLastName, cea.EpiFirstName, cea.EpiMI,
	-- BC - Added 7.18.25 for validation to HCHB
	CONCAT_WS(' ', 
		CONCAT(cea.EpiLastName, ', ',  cea.EpiFirstName),
		cea.EpiMI) AS PatientName,
	CONCAT_WS(' ',
		CONCAT(DW.WorkerLastName, ', ', DW.WorkerFirstName),
		DW.WorkerMiddleInitial) AS WorkerName,
	dw.WorkerId,
	dw.JobTitle,
	dw.JobDescriptionCode,
	dw.WorkerHomeBranch
	from
dbo.ClientSchedVisits CSV with (nolock) -- cant use vw_dimClientEpisodeVisitWithWorkerId because it doesnt have prod points (or a way to join to service codes)
	inner join
	dbo.VisitStatuses VS with (nolock)
	on CSV.CsvStatus = VS.vsStatus and csv.SourceSystem = vs.SourceSystem
		/** need join to task status table **/
	inner join
	dbo.ServiceCodes SC with (nolock) 
	on CSV.CsvScid = SC.scid and csv.SourceSystem = sc.SourceSystem
	inner join
	dbo.Disciplines D with (nolock)
	ON SC.ScDiscipline = D.DscCode and sc.SourceSystem = d.SourceSystem
	inner join
	dbo.ClientEpisodesAll CEA with (nolock) 
	on CSV.CsvEpiId = CEA.EpiId and csv.SourceSystem = cea.SourceSystem
	inner join
	dbo.dimBranch B with (nolock)
	on CEA.EpiBranchcode = B.BranchCode and cea.SourceSystem = b.SourceSystem
	inner join
	dbo.dimPatient P with (nolock)
	on CEA.EpiPaId = P.PatientId and cea.SourceSystem = p.SourceSystem
	left join
	h as EBP
	on CEA.epiId = EBP.episodeId  and CEA.SourceSystem = EBP.SourceSystem
	and csv.CsvSchedDate between EBP.BPStartDate and EBP.BPEndDate
	left join
	dbo.ClientEpisodeVisitsAll CEV with (nolock) 
	on CSV.CsvId = CEV.CevCsvId and csv.SourceSystem = cev.SourceSystem and cev.CevDeleted = 0
	left join
	dbo.ClientEpisodeFs CEFS with (nolock)
	on cea.epiid = cefs.CefsEpiId and cefs.CefsPs = 'P' and cefs.CefsActive = 'Y' and cea.SourceSystem = cefs.SourceSystem
	--left join HCPHCSQuery hcpcs (nolock)
	--on CSV.CsvId = hcpcs.CsvId and CSV.SourceSystem = hcpcs.SourceSystem
	left join
	dbo.VisitMissedReasons vmr with (nolock)
	on CSV.CsvVmId = vmr.VmId AND CSV.SourceSystem=VMR.SourceSystem
LEFT JOIN diminsurance i (nolock)
	on CEFS.CefsPsid=i.InsuranceId	and cefs.SourceSystem=i.SourceSystem
	LEFT JOIN dbo.dimWorker dw WITH (NOLOCK)
    ON CEV.CevAgId = dw.WorkerId
    AND dw.SourceSystem = CEV.SourceSystem
	where
	csv.CsvSchedDate BETWEEN DATEADD(M,-13,DATEADD(M,DATEDIFF(M,0,GETDATE()),0)) AND GETDATE() +60
	and cea.EpiSlId = 1
	--and csv.SourceSystem = 'Abode'
	and cea.EpiStatus not in ('DELETED', 'PENDING','NON-ADMIT')
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
	and (CEV.CevDeleted<>1 or CEV.CevDeleted is null)-- exclude deleted records where status is completed

)

select distinct
	skVisitDateKey,
	VisitId,
	skScheduleDateKey,
	LastUpdateDate,
	ScheduledVisitId,
	--AdmissionId,
	episodeId,
	PatientName,
	bpKey,
	billingPeriodStartDate as skbillingPeriodStartDateKey,
	billingPeriodEndDate as skbillingPeriodEndDateKey,
	BillingPeriodSequence,
	episodeStartDate as skepisodeStartDateKey,
	episodeEndDate as skepisodeEndDateKey,
	startOfCareDate as skstartOfCareDateKey,
	CompletedVisits,
	InHomeVisits_VisitNumber,
	taskCount,
	MissedVisit,
	NVDC,
	DischargeTasks,
	Visitbillable,
	ServiceBillable,
	payable,
	OpenClosedFlag,
	VisitBetweenSOEandEOE,
	WorkerId,
	WorkerName,
	JobTitle,
	JobDescriptionCode,
	WorkerHomeBranch,
	taskDesc,
	taskType,
	taskCode,
	CsvVisitNumber as VisitNumber,
	taskJobCode,
	Discipline as taskDiscipline,
	taskStatus,
	VisitMissedReason,
	PatientId,
	InsuranceId,
	InsuranceTypeId,
	InsuranceType,
	BranchCode,
	skOrgKey,
	[Location],
	EpiSlId as ServiceLineId,
	--HCPCS,
	HIPPS,
	LupaThreshold,
    ClinicalGrouping,
	Timing,
	FunctionalImpLevel,
	ComorbidityAdjustment,
	CaseMixWeight,
	SourceSystem,
	CevDeleted,
	epistatus

from
	TaskDetails 
	   
WHERE
    (InHomeVisits_VisitNumber = 1
        OR MissedVisit = 1
        OR NVDC = 1
        OR DischargeTasks = 1)
--and PatientName = 'NUTTER, DOUGLAS K'
--and episodeId = 913607


order by skScheduleDateKey DESC