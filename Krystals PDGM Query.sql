
drop table if exists #ScExclusionList
drop table if exists #actualRatePeriodByBP
drop table if exists #admissionBillingPeriods
drop table if exists #EpisodeBillingPeriods
drop table if exists #episodeNoVisits
drop table if exists #episodeVisits
drop table if exists #episodeVisitsSummary
drop table if exists #potentialRPByEpisodeBP
drop table if exists #recertCount


	select
		sc.ScId,
		sc.ScCode
	into
		#ScExclusionList
	from
		dbo.HCHBServiceCodes sc with (nolock)
	where
		sc.ScCode in ('OT66','PT66','RN66','ST66','RN66X','PDR66X','RN66-IV','RN90','RN91','RN92',
		'SN90','SN91','RN93','RN94','SN93','SN95','RN95','RN96','SN92','SN94','SN96','MS-BIPA','PT-BIPA',
		'OT-BIPA','SN-BIPA','ST-BIPA','PT-FUNC','OT-FUNC','RN-SUP','PT-SUP','OT-SUP',
		'SN97','PT97','RN97','ST-FUNC','SN98','RN98','SN-CHF','SN-PRE','ST-PRE','OT-PRE',
		'PT-PRE','RN-BIPA','RN-PRE','SN-CONCARE','PT-CONCARE','OT-CONCARE','CT-CONCARE','PA-CONCARE','SN-NOMNC',
		'CT-NOMNC','ST-NOMNC','PT-NOMNC','OT-NOMNC','RN-NOMNC','MS-NOMNC','MS-CONCARE','PA-NOMNC','MS-SUP',
		'OT44','PT44','RN44','ST44','PDR44X','RN44X','RN44-IV')

	select
		distinct
		ca.CaId,
		cea.EpiId,
		cea.EpiStartOfEpisode,
		ROW_NUMBER() OVER(PARTITION BY ca.CaId ORDER BY cea.EpiStartOfEpisode) AS RecCNT,
		1 as RecertTask
	into
		#recertCount
	from
		dbo.HCHBClientAdmission ca with (nolock)
		inner join
		dbo.HCHBClientEpisodesAll cea with (nolock)
		on ca.CaPaId = cea.EpiPaId and ca.CaSlId = cea.EpiSlId and ca.CaSOCDate = cea.EpiSOCDate and ca.SourceSystem = cea.SourceSystem
	where
		cea.EpiStatus = 'RECERTIFIED'
		and ca.SourceSystem = 'Abode'

	select
		distinct
		cea.EpiId as EpisodeId,
		pp.PpPeriodnumber,
		pp.PpStartDate,
		pp.PpEndDate,
		rp.RpId,
		rp.RpCode,
		rp.RpSoeEffectiveFrom,
		rp.RpSoeEffectiveTo
	into
		#potentialRPByEpisodeBP
	from
		dbo.HCHBClientEpisodesAll cea
		inner join
		dbo.HCHBClientEpisodeFs cefs
		on cea.EpiId = cefs.CefsEpiId and /*cefs.CefsPs = 'P' and*/ cea.SourceSystem = cefs.SourceSystem
		inner join
		dbo.HCHBPdgmPeriod pp
		on cefs.CefsId = pp.PpCefsId and pp.PpDeleted = 0
		inner join
		dbo.HCHBRatePeriod rp
		on pp.PpStartDate between rp.RpSoeEffectiveFrom and rp.RpSoeEffectiveTo
			and rp.RpActive = 'Y' and rp.RpSltId = 1 and rp.RpRptId = 5 and cea.SourceSystem = rp.SourceSystem
	where
		cea.SourceSystem = 'Abode'
		and cea.EpiSlId = 1

select 
	t1.EpisodeId,
	t1.PpPeriodnumber,
	t1.PpStartDate,
	t1.PpEndDate,
	t1.RpId as RatePeriodId,
	t1.RpCode,
	t1.RpSoeEffectiveFrom,
	t1.RpSoeEffectiveTo 
into
	#actualRatePeriodByBP
from 
	#potentialRPByEpisodeBP t1
	inner join 
	(select episodeId, PpPeriodNumber, min(rpsoeeffectivefrom) as minEffectiveFrom from #potentialRPByEpisodeBP group by episodeId, PpPeriodNumber) t2
	on t1.EpisodeId = t2.EpisodeId and t1.PpPeriodnumber = t2.PpPeriodnumber and t1.RpSoeEffectiveFrom = t2.minEffectiveFrom


	select distinct
		pp.PpId as PPId,
		case
			when pp.PpCurrentHipps <> '' then pp.PpCurrentHipps
			when pp.PpInitialHipps <> '' then pp.PpInitialHipps
			else null
		end as HIPPS,
		coalesce(phc.phlupathreshold, phi.phlupathreshold) as LupaThreshold,
		cea.EpiId as episodeId,
		cefs.CefsPsId as BPInsuranceId,
		pp.PpStartDate as BPStartDate,
		pp.PpEndDate as BPEndDate,
		pp.PpPeriodNumber as BPNumber,
		ca.CaId as AdmissionId,
		cefs.CefsPsId as InsuranceId,
		cea.SourceSystem as SourceSystem
	into
		#EpisodeBillingPeriods
	from
		dbo.HCHBClientEpisodesAll cea with (nolock)
		inner join
		dbo.HCHBClientEpisodeFs cefs with (nolock)
		on cea.EpiId = cefs.CefsEpiId and cea.SourceSystem = cefs.SourceSystem
		inner join
		dbo.HCHBPdgmPeriod pp with (nolock)
		on cefs.CefsId = pp.PpCefsId and cefs.SourceSystem = pp.SourceSystem
		left join
		dbo.HCHBClientAdmission ca with (nolock)
		on cea.EpiPaId = ca.CaPaId and cea.EpiSlId = ca.CaSlId and cea.EpiSOCDate = ca.CaSOCDate and cea.SourceSystem = ca.SourceSystem
		left join
		#ActualRatePeriodByBP erp
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
		and cea.EpiStatus not in ('DELETED', 'PENDING')
		and cea.EpiSlid = 1
		and cea.SourceSystem = 'Abode'

	select
		ca.CaId,
		ebp.BPStartDate,
		ROW_NUMBER() OVER(PARTITION BY ca.CaId ORDER BY ebp.BPStartDate) AS BPNum,
		ca.SourceSystem as SourceSystem
	into
		#admissionBillingPeriods
	from
		dbo.HCHBClientAdmission ca with (nolock)
		inner join
		dbo.HCHBClientEpisodesAll cea with (nolock)
		on ca.CaPaId = cea.EpiPaId and ca.CaSlid = cea.EpiSlId and ca.CaSOCDate = cea.EpiSOCDate and ca.SourceSystem = cea.SourceSystem
		inner join
		#EpisodeBillingPeriods ebp
		on cea.EpiId = ebp.episodeId
	where
		ca.SourceSystem = 'Abode'

	select distinct
		cea.EpiId,
		ca.CaId as AdmissionId,
		ebpWithVisits.InsuranceId as InsuranceId,
		cev.CevVisitDate,
		ebpWithVisits.BPNumber,
		ebpWithVisits.BPStartDate,
		ebpWithVisits.BPEndDate,
		count(cev.CevId) as visits,
		d.DscDesc as taskType,	
		case when DscCode = 'SN' then count(cev.CevId) else 0 end as SNVisits,
		case when DscCode = 'OT' then count(cev.CevId) else 0 end as OTVisits,
		case when DscCode = 'PT' then count(cev.CevId) else 0 end as PTVisits,
		case when DscCode = 'ST' then count(cev.CevId) else 0 end as STVisits,
		case when DscCode = 'MSW' then count(cev.CevId) else 0 end as MSWVisits,
		case when DscCode = 'HHA' then count(cev.CevId) else 0 end as HHAVisits,
		isnull(ebpWithVisits.LupaThreshold,0) as LupaThreshold,
		cea.SourceSystem as SourceSystem
	into
		#episodeVisits
	from
		dbo.HCHBClientEpisodesAll cea with (nolock)
		inner join
		dbo.HCHBClientSchedVisits csv with (nolock)
		on cea.EpiId = csv.CsvEpiId and cea.SourceSystem = csv.SourceSystem
		inner join
		dbo.HCHBClientEpisodeVisitsAll cev with (nolock)
		on csv.CsvId = cev.CevCsvId and csv.SourceSystem = cev.SourceSystem and cev.CevBillable = 1 and cev.CevDeleted = 0
		inner join
		dbo.HCHBServiceCodes sc with (nolock)
		on cev.CevScId = sc.ScId and cev.SourceSystem = sc.SourceSystem
		inner join
		dbo.HCHBDisciplines d with (nolock)
		on sc.ScDiscipline = d.DscCode and sc.SourceSystem = d.SourceSystem
		left join
		dbo.HCHBClientAdmission ca with (nolock)
		on cea.EpiPaId = ca.CaPaId and cea.EpiSlId = ca.CaSlId and cea.EpiSOCDate = ca.CaSOCDate and cea.SourceSystem = ca.SourceSystem
		left join
		#EpisodeBillingPeriods ebpWithVisits
		on cev.CevEpiId = ebpWithVisits.episodeId and cev.CevVisitDate between ebpWithVisits.BPStartDate and ebpWithVisits.BPEndDate and cev.SourceSystem = ebpWithVisits.SourceSystem
	where
		cea.EpiSlId = 1
		and cea.epistatus not in ('deleted', 'non-admit', 'pending')
		/**and tasks not in exclusion list**/
		and cev.CevScId not in (select scid from #ScExclusionList)
	group by
		EpiId, ca.CaId, CevVisitDate, DscCode, ebpWithVisits.BPNumber, 
		d.DscDesc, cea.SourceSystem, ebpWithVisits.InsuranceId, ebpWithVisits.BPStartDate, ebpWithVisits.BPEndDate, isnull(ebpWithVisits.LupaThreshold,0)

	select distinct
		cea.EpiId,
		ebp.BPNumber,
		ebp.BPStartDate,
		ebp.BPEndDate,
		ca.CaId as AdmissionId,
		ebp.InsuranceId as InsuranceId,
		0 as visits,
		NULL as taskType,	
		0 as SNVisits,
		0 as OTVisits,
		0 as PTVisits,
		0 as STVisits,
		0 as MSWVisits,
		0 as HHAVisits,
		isnull(ebp.LupaThreshold, 0) as LupaThreshold,
		cea.SourceSystem as SourceSystem
	into
		#episodeNoVisits
	from
		dbo.HCHBClientEpisodesAll cea with (nolock)
		left join
		#episodeVisits ev
		on cea.epiid = ev.EpiId and cea.SourceSystem = ev.SourceSystem
		left join
		#EpisodeBillingPeriods ebp
		on cea.epiid = ebp.episodeId and cea.SourceSystem = ebp.SourceSystem
		left join
		dbo.HCHBClientAdmission ca with (nolock)
		on cea.EpiPaId = ca.CaPaId and cea.EpiSlId = ca.CaSlId and cea.EpiSOCDate = ca.CaSOCDate and cea.SourceSystem = ca.SourceSystem
	where
		cea.EpiSlId = 1
		and cea.epistatus not in ('deleted', 'non-admit', 'pending')
		and ev.epiid is null

select * into #episodeVisitsSummary
from
	(select 
		distinct 
		ev.EpiId, 
		ev.AdmissionId, 
		coalesce(ev.InsuranceId, cefs.CefsPsId) as InsuranceId, 
		--ev.InsuranceId,
		ev.BPNumber,
		ev.BpStartDate,
		ev.BPEndDate,
		min(ev.CevVisitDate) as skFirstBillableVisitDateKey,
		sum(ev.SNVisits) as SNVisits, --SNCompletedVisits , 
		sum(ev.OTVisits) as OTVisits, --f.OTCompletedVisits,
		sum(ev.PTVisits)  as PTVisits,-- f.PTCompletedVisits,
		sum(ev.STVisits) as STVisits, --f.STCompletedVisits, 
		sum(ev.MSWVisits) as MSWVisits, --f.MSWCompletedVisits, 
		sum(ev.HHAVisits) as HHAVisits, --f.HHACompletedVisits
		sum(ev.SNVisits)+sum(ev.OTVisits) +sum(ev.PTVisits)+ sum(ev.STVisits) +sum(ev.MSWVisits) + sum(ev.HHAVisits)as TotalVisits,
		ev.LupaThreshold,
		ev.SourceSystem
	from
		#episodeVisits ev
		left join
		dbo.HCHBClientEpisodeFs cefs with (nolock)
		on ev.epiid = cefs.CefsEpiId and ev.SourceSystem = cefs.SourceSystem and cefs.CefsPs = 'P' and cefs.CefsActive = 'Y'
	group by
		ev.EpiId, 
		ev.AdmissionId, 
		coalesce(ev.InsuranceId, cefs.CefsPsId), 
		ev.BPNumber,
		ev.BpStartDate,
		ev.BPEndDate,
		ev.LupaThreshold,
		ev.SourceSystem
	UNION ALL
	select 
		distinct 
		ev.EpiId, 
		ev.AdmissionId, 
		coalesce(ev.InsuranceId, cefs.CefsPsId) as InsuranceId,  
		ev.BPNumber,
		ev.BpStartDate,
		ev.BPEndDate,
		null as skFirstBillableVisitDateKey,
		sum(ev.SNVisits) as SNVisits, --SNCompletedVisits , 
		sum(ev.OTVisits) as OTVisits, --f.OTCompletedVisits,
		sum(ev.PTVisits)  as PTVisits,-- f.PTCompletedVisits,
		sum(ev.STVisits) as STVisits, --f.STCompletedVisits, 
		sum(ev.MSWVisits) as MSWVisits, --f.MSWCompletedVisits, 
		sum(ev.HHAVisits) as HHAVisits, --f.HHACompletedVisits
		sum(ev.SNVisits)+sum(ev.OTVisits) +sum(ev.PTVisits)+ sum(ev.STVisits) +sum(ev.MSWVisits) + sum(ev.HHAVisits)as TotalVisits,
		ev.LupaThreshold,
		ev.SourceSystem
	from
		#episodeNoVisits ev
		left join
		dbo.HCHBClientEpisodeFs cefs with (nolock)
		on ev.epiid = cefs.CefsEpiId and ev.SourceSystem = cefs.SourceSystem and cefs.CefsPs = 'P' and cefs.CefsActive = 'Y'
	group by
		ev.EpiId, 
		ev.AdmissionId, 
		coalesce(ev.InsuranceId, cefs.CefsPsId), 
		ev.BPNumber,
		ev.BpStartDate,
		ev.BPEndDate,
		ev.LupaThreshold,
		ev.SourceSystem
) as tmp

select
	CASE 
		WHEN evs.TotalVisits is null or evs.TotalVisits=0 THEN 1 
		ELSE 0 
	END AS BP0Visits, 
	CASE 
		WHEN evs.BPNumber is not null and isnull(evs.TotalVisits, 0) > 0 THEN 1 
		ELSE 0 
	END as BillingPeriodCount,
	evs.AdmissionId,
	evs.EpiId,
	evs.BPNumber as BillingPeriodSequence,
	convert(varchar(8), evs.skFirstBillableVisitDateKey, 112) as skFirstBillableVisitDateKey,
	convert(varchar(8), cea.EpiSocDate, 112) as skStartOfCareDateKey,
	p.PatientId as nkPatientKey,
	evs.InsuranceId as nkInsuranceKey,
	b.Id as skOrgKey,
	left(b.ForeignCode, 4) as Operation,
	right(b.ForeignCode, 5) as [Location],
	cea.EpiStartOfEpisode as EpisodeStartDate,
	cea.EpiEndOfEpisode as EpisodeEndDate,
	evs.BPStartDate as BillingPeriodStartDate,
	evs.BPEndDate as BillingPeriodEndDate,
	cea.EpiDischargeDate as DischargeDate,
	evs.SNVisits as SNCompletedVisits,
	evs.OTVisits as OTCompletedVisits,
	evs.PTVisits as PTCompletedVisits,
	evs.STVisits as STCompletedVisits,
	evs.MSWVisits as MSWCompletedVisits,
	evs.HHAVisits as HHACompletedVisits,
	evs.TotalVisits as CompletedVisits,
	case
		when evs.bpStartDate > evs.bpEndDate then 0
		when evs.totalVisits = 0 then 0
		when evs.BPEndDate < getdate() and evs.TotalVisits < evs.LupaThreshold then 1
		else 0
	end as IsLupa,
	evs.LupaThreshold as LupaVisitThreshold,
	isnull(rc.recCnt, 0) as RecCnt,
	isnull(rc.recertTask, 0) as recertTask,
	abp.BPNum as BPNum
from
	#episodeVisitsSummary evs
	inner join
	dbo.HCHBClientEpisodesAll cea with (nolock)
	on evs.EpiId = cea.EpiId and evs.SourceSystem = cea.SourceSystem
	inner join
	dbo.dimPatient p with (nolock)
	on cea.epipaid = p.PatientId and cea.SourceSystem = p.SourceSystem
	inner join
	dbo.dimBranch b with (nolock)
	on cea.EpiBranchcode = b.BranchCode and cea.SourceSystem = b.SourceSystem
	inner join
	dbo.dimInsurance i with (nolock)
	on evs.InsuranceId = i.InsuranceId and evs.SourceSystem = i.SourceSystem
	left join
	#recertCount rc
	on evs.EpiId = rc.EpiId
	left join
	#admissionBillingPeriods abp
	on evs.AdmissionId = abp.caid and evs.BPStartDate = abp.BPStartDate
where
	cea.EpiStartOfEpisode >=DATEADD(M,-60,DATEADD(M,DATEDIFF(M,0,GETDATE()),0))  
	AND cea.EpiStartOfEpisode < GETDATE()
	and i.insurancetypeid in (57, 25007, 25017)