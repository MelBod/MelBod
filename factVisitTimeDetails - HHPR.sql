SELECT     
ActualEndDateTime
,ActualStartDateTime
,AgencyId
,AgentId
,AgentWorkerKey
,BranchCode
,BranchKey
,ClientEpisodeVisitId
,ClientEpisodeVisitKey
,CompanyId
,DischargeDate
,DocTimeDateNotOnServiceDate
,EmployeeId
,EndOfEpisodeDate
,EpisodeId
,FLOOR(PayableDocumentationTimeMins / 60) AS PayableDocumentationTimeMins
,FLOOR(PayableInHomeTimeMins / 60) AS PayableInHomeTimeMins
,FLOOR(PayableTotalTimeMins / 60.0) AS PayableTotalTimeMins
,FLOOR(PayableTravelTimeMins / 60) AS PayableTravelTimeMins
,isClientEpisodeVisitBillable

,isMileagePayable
,isNonVisitTime
,isServiceActive
,isStopEventCompleted
,isStopEventIncomplete
,isVisitTime
,Location
,MaxPayableCompleteTime
,MileageEnd
,MileagePayMethod
,MileageStart
,MinPayableEndDateTime
,MinPayableStartDateTime
,PatientId
,PatientVisitNumber
,PayableDocumentationTimeHours
,PayableDocumentationTimeMins
,PayableGrandTotalTimeHours
,PayableGrandTotalTimeMins
,PayableInHomeTimeHours
,PayableInHomeTimeMins
,PayableTotalTimeHours
,PayableTotalTimeMins
,PayableTravelTimeHours
,PayableTravelTimeMins
,ScheduledVisitId
,ScheduledVisitKey
,ServiceCodeId
,ServiceTripFee
,SourceSystem
,startdate
,StartOfCareDate
,StartofEpisodeDate
,StartTime
,StartToStopMins
,StopDate
,StopTime
,TeamId
,VisitDate



FROM dbo.factVisitTimeDetails

WHERE SourceSystem = 'Abode'
     AND ServiceLineTypeId = 1
     AND VisitDate >= DATEFROMPARTS(YEAR(DATEADD(MONTH, - 7, GETDATE())), MONTH(DATEADD(MONTH, - 7, GETDATE())), 1)
     AND VisitDate < DATEADD(DAY, 1, CAST(GETDATE() AS DATE))
     and isDeleted = 0

	 --need a distinct count of ScheduledVisitId
	 --need a sum of all payable fields by worker
	 --aggregate everything by week
	 --number of patients by worker by week
	 --