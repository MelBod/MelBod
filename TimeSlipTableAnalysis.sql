 SELECT  Id
      ,TstId --if 4 then nva 
      ,TstDesc
      ,TstActive
      ,TstRequired
      ,TstTscid --service code (nva service code = 2)
      ,TstInsertDate
      ,TstLastUpdate
      ,TstRequiredSequence
      ,CreatedDateTime
      ,ModifiedDateTime
      ,SourceSystem
  FROM dbo.TIMESLIPTYPES
  where SourceSystem = 'Abode'

  --same as dbo.TIMESLIPTYPES
  SELECT  Id
      ,TimeSlipTypeId
      ,TimeSlipTypeDescription
      ,TimeSlipTypeCategoryName
      ,RequiredFlag
      ,ActiveFlag
     
  FROM dbo.dimTimeSlipType
  where SourceSystem = 'Abode'

SELECT distinct
      TimeSlipTypeKey
      ,TimeSlipCategoryKey
      ,TimeSlipEventStartKey
      ,TimeSlipEventStopKey
      ,TimeSlipTypeId --TstId in TIMESLIPTYPES (NO 4, ONLY 1 - 3)
      ,TimeSlipCategoryId
      ,TimeSlipStartEventId
      ,TimeSlipStopEventId
  FROM dbo.factVisitTimeDetails
  where SourceSystem = 'Abode'


