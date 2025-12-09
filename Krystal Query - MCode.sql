-- DETERMINE MEDI-MEDI AT SOC
WITH SOC
AS (
SELECT DISTINCT m0.AdmissionId
,m0.M0150CPayMcareFfs -- TRADITIONAL AT SOC

FROM dbo.AbodeBranchScoreCardM0Item_h m0 WITH (NOLOCK)

WHERE m0.M0100AssmtReason = '01'
AND m0.M0150CPayMcareFfs = 1
)
,
-- DETERMINE PAYOR AT DISCHARGE
TFR
AS (
SELECT DISTINCT m0.AdmissionId
,m0.M0150CPayMcareFfs -- TRADITIONAL AT TRANSFER/DISCHARGE 

FROM dbo.AbodeBranchScoreCardM0Item_h m0 WITH (NOLOCK)

WHERE m0.M0100AssmtReason IN (
'06'
,'07'
,'09'
)
AND m0.M0150CPayMcareFfs = 0
AND DATEDIFF(day, m0.M0030StartCareDt, m0.M0906DcTranDthDt) <= 60
)
,
-- GET FIRST HOSPITALIZATION DATE
H
AS (
SELECT DISTINCT m0.admissionId
,MIN(m0.M0906DcTranDthDt) AS TFRDT

FROM dbo.AbodeBranchScoreCardM0Item_h m0 WITH (NOLOCK)

WHERE m0.M0100AssmtReason IN (
'06'
,'07'
)
AND m0.M2410InpatFacility = '01'
AND m0.M0906DcTranDthDt IS NOT NULL

GROUP BY m0.admissionid
/******************** ADDED 11/22/2022 SF **********************/
)
,
-- IDENTIFY PRIOR HOSPITALIZATIONS (WHERE DATE BETWEEN PRE-BHS HOSPITALIZATION DISCHARGE IS LESS THAN OR = 5 DAYS TO SOC AT BHS
IP_CTE
AS (
SELECT DISTINCT m0.admissionId
,MIN(m0.M1005InpDischargeDt) AS IPDC
,MIN(m0.M0030StartCareDt) AS HHSOC
,DATEDIFF(day, MIN(m0.M1005InpDischargeDt), MIN(m0.M0030StartCareDt)) DaysDiff
,'Short-Stay Acute hospital (IPP S)' AS 'DischargedInpatientFacility'

FROM dbo.AbodeBranchScoreCardM0Item_h m0 WITH (NOLOCK)

WHERE m0.M0100AssmtReason = '01'
AND m0.M1000DcIpps14Da = 1
AND m0.M1005InpDischargeDt IS NOT NULL
AND DATEDIFF(day, m0.M1005InpDischargeDt, m0.M0030StartCareDt) <= 5

GROUP BY m0.admissionid
--ORDER BY 
-- m0.admissionid
)
,
-- COMPARE PRE-BHS HOSP TO BHS HOSP TO GET FIRST REHOSP DATE
H30_CTE
AS (
SELECT DISTINCT InP.admissionId
,MIN(H.TFRDT) AS ReHospTFRDT

FROM H WITH (NOLOCK)

JOIN IP_CTE InP ON H.admissionId = InP.admissionId

GROUP BY InP.admissionid
)
,Diagnosis_CTE
AS (
SELECT DISTINCT cdpId
,cdpEpiId
,cdpdiICDCode
,cdpdiICDVersionID
,cdpDiICDTypeCode
,cdpSortOrder
,cdpSymptomSeverity
,RANK() OVER (
PARTITION BY cdpEpiId ORDER BY cdpSortOrder
,cdpId
) AS diagnosisRank
,SourceSystem

FROM [dbo].[HCHBClientDiagnosesAndProcedures]

WHERE SourceSystem = 'Abode'
AND [CdpDiICDVersionId] = 10
)
,PrimaryDiagnonsis_CTE
AS (
SELECT DISTINCT cdpepiid
,CASE 
WHEN diagnosisrank = 1
THEN cdpdiICDCode
END AS [ICD10 Code]
,dimDiagnosis.DiagnosisName AS [Primary Diagnosis]
,SourceSystem

FROM Diagnosis_CTE Diagnosis

JOIN [dbo].[dimDiagnosis] ON Diagnosis.cdpdiICDCode = [dimDiagnosis].DiagnosisCode

WHERE diagnosisrank = 1
)
,SecondaryDiagnosis_CTE
AS (
SELECT DISTINCT cdpepiid
,CASE 
WHEN diagnosisrank = 2
THEN cdpdiICDCode
END AS [ICD10 Code]
,dimDiagnosis.DiagnosisName AS [Secondary Diagnosis]
,SourceSystem

FROM Diagnosis_CTE Diagnosis

JOIN [dbo].[dimDiagnosis] ON Diagnosis.cdpdiICDCode = [dimDiagnosis].DiagnosisCode

WHERE diagnosisrank = 2
)

SELECT H30.ReHospTFRDT AS FirstReHspDt
,CASE 
WHEN H30.ReHospTFRDT = m0.M0906DcTranDthDt
THEN 1
ELSE 0
END AS FirstReHsp
,CASE 
WHEN InP.IPDC IS NULL
THEN 0
ELSE InP.DaysDiff
END AS IPDCtoHH
,PD.[ICD10 Code] AS [Primary ICD10 Code]
,PD.[Primary Diagnosis]
,SD.[ICD10 Code] AS [Secondary ICD10 Code]
,SD.[Secondary Diagnosis]
,
/******************** END OF ADDITIONS 11/22/2022 SF **********************/
m0.AdmissionId
,cefs.CefsPsId
,cefs.CefsPtId
,p.LastName
,p.PatientId AS PatientId
,CASE 
WHEN H.TFRDT = M0906DcTranDthDt
THEN 1
ELSE 0
END AS FirstHsp
,h.TFRDT AS FirstHspDt
,SOC.M0150CPayMcareFfs AS SOCMediTrad
,CASE 
WHEN SOC.M0150CPayMcareFfs = 1
THEN 'N'
ELSE 'Y'
END AS SOCMediTradEx
,CASE 
WHEN TFR.M0150CPayMcareFfs = 0
THEN 'Y'
ELSE 'N'
END AS TFRMediTradEx
,CASE 
WHEN IPDC IS NOT NULL
THEN 'N'
ELSE 'Y'
END AS 'InpDischEx'
,m0.Id AS skM0ItemKey
,m0.VisitId
,m0.EpisodeId
,o.skOrgKey
,o.Location
,o.BranchShortName
,o.ClinicShortName
,i.skInsuranceKey
,i.nkInsuranceKey AS InsuranceId
,i.InsuranceType
,m0.IsLupa
,m0.LupaThreshold AS LupaVisitThreshold
,m0.TotalVisits
,CASE 
WHEN m0.IsLupa = 1
THEN 'Y'
ELSE 'N'
END AS LUPAEx
,m0.M0150CPayMcareFfs
,m0.M0150CpayMcareHmo
,m0.M0150CpayMcaidFfs
,m0.M0150CpayMcaidHmo
,CASE 
WHEN m0.M0150CPayMcareFfs = 1
THEN '1 - Medicare (traditional fee-for-service)'
WHEN m0.M0150CpayMcareHmo = 1
THEN '2 - Medicare (HMO/managed care/Advantage plan)'
WHEN m0.M0150CpayMcaidFfs = 1
THEN '3 - Medicaid (traditional fee-for-service)'
WHEN m0.M0150CpayMcaidHmo = 1
THEN '4 - Medicaid (HMO/managed care)'
ELSE 'Not Medi-Medi'
END AS MediPaySource
,m0.M1005InpDischargeDt
,-- inpatient dischg date (prior to SOC)
m0.M1000DcIpps14Da
,-- inpatient dischg from hospital
m0.M0030StartCareDt
,m0.M0032RocDtNa
,m0.M0032RocDt
,cea.EpiSocDate AS StartOfCareDate
,cea.EpiStartOfEpisode AS EpisodeStartDate
,CASE 
WHEN m0.M0080AssessorDiscipline = '01'
THEN 'RN'
WHEN m0.M0080AssessorDiscipline = '02'
THEN 'PT'
WHEN m0.M0080AssessorDiscipline = '03'
THEN 'SLP/ST'
WHEN m0.M0080AssessorDiscipline = '04'
THEN 'OT'
ELSE m0.M0080AssessorDiscipline
END AssessorDiscipline
,m0.M0100AssmtReason
,CASE 
WHEN m0.M0100AssmtReason = '01'
THEN 'Starting'
WHEN m0.M0100AssmtReason = '03'
THEN 'Starting'
WHEN m0.M0100AssmtReason = '06'
THEN 'Ending'
WHEN m0.M0100AssmtReason = '09'
THEN 'Ending'
WHEN m0.M0100AssmtReason = '07'
THEN 'Ending'
WHEN m0.M0100AssmtReason = '08'
THEN 'Ending'
ELSE m0.M0100AssmtReason
END AssessmentType
,CASE 
WHEN m0.M0100AssmtReason = '01'
THEN 'Start of Care'
WHEN m0.M0100AssmtReason = '03'
THEN 'Resumption of Care'
WHEN m0.M0100AssmtReason = '06'
THEN 'Transfer w/o Discharge'
WHEN m0.M0100AssmtReason = '09'
THEN 'Discharge'
WHEN m0.M0100AssmtReason = '07'
THEN 'Transfer w/ Discharge'
WHEN m0.M0100AssmtReason = '08'
THEN 'Death'
ELSE m0.M0100AssmtReason
END AssessmentReason
,m0.M2410InpatFacility
,CASE 
WHEN m0.M2410InpatFacility = 'NA'
THEN 'No Inpatient Facility Admission'
WHEN m0.M2410InpatFacility = '01'
THEN 'Hospital'
WHEN m0.M2410InpatFacility = '02'
THEN 'Rehabilitation facility'
WHEN m0.M2410InpatFacility = '03'
THEN 'Nursing home'
WHEN m0.M2410InpatFacility = '04'
THEN 'Hospice'
ELSE m0.M2410InpatFacility
END InpatientFacility
,CASE 
WHEN m0.M2410InpatFacility <> '01' /* not hospital */
THEN 'No'
WHEN m0.M2410InpatFacility IS NULL
THEN 'No'
WHEN m0.M2410InpatFacility = '01'
AND m0.M2430HospSchldTrtmt = 1
THEN 'No' -- hospital scheduled treatment
WHEN m0.M2410InpatFacility = '01'
AND isnull(m0.M2430HospSchldTrtmt, 0) <> 1
THEN 'Yes' -- hospital not scheduled
ELSE 'No'
END ACH
,m0.M2430HospSchldTrtmt
,m0.M0090InfoCompletedDt AS AssessmentDate
,CASE 
WHEN m0.M0100AssmtReason IN (
'06'
,'07'
,'08'
,'09'
)
THEN ISNULL(ISNULL(m0.M0906DcTranDthDt, m0.M0090InfoCompletedDt), cea.EpiDischargeDate)
ELSE NULL
END AS TransferDthDschgDate
,CASE 
WHEN m0.M0100AssmtReason IN (
'06'
,'07'
,'08'
,'09'
)
THEN m0.M0906DcTranDthDt
ELSE NULL
END AS M0906DcTranDthDt
,m0.M0090InfoCompletedDt
,cea.EpiDischargeDate AS DischargeDate
,cea.EpiSlId AS ServiceLineId
,--added to create mrn in power query 5/6/2025 kp
cea.EpiBranchcode AS BranchCode
,cea.SourceSystem

FROM dbo.AbodeBranchScoreCardM0Item_h m0 WITH (NOLOCK)

INNER JOIN dbo.ClientEpisodesAll cea WITH (NOLOCK) -- changed from HCHB table 5/6/2025 kp
ON m0.EpisodeId = cea.epiId
AND m0.SourceSystem = cea.SourceSystem

LEFT JOIN dbo.HCHBClientEpisodeFs cefs WITH (NOLOCK) ON cea.epiId = cefs.cefsEpiid
AND cefs.cefsPs = 'P'
AND cefs.cefsActive = 'Y'
AND cea.SourceSystem = cefs.SourceSystem

LEFT JOIN dbo.vw_AbodeBranchScoreCardDimInsurance i ON cefs.CefsPsId = i.nkInsuranceKey

INNER JOIN dbo.dimPatient p WITH (NOLOCK) ON cea.epiPaid = p.PatientId
AND cea.SourceSystem = p.SourceSystem

INNER JOIN dbo.vw_AbodeBranchScoreCardDimOrg o WITH (NOLOCK) ON cea.EpiBranchcode = o.BranchCode

LEFT JOIN H H ON m0.AdmissionId = H.AdmissionId

LEFT JOIN SOC SOC ON m0.AdmissionId = SOC.AdmissionId

LEFT JOIN TFR TFR ON m0.AdmissionId = TFR.AdmissionId

LEFT JOIN IP_CTE InP(NOLOCK) -- JOIN TO PRIOR INPATIENT DATE
ON InP.AdmissionId = m0.AdmissionId

LEFT JOIN H30_CTE H30(NOLOCK) -- JOIN TO PRIOR INPATIENT DATE
ON H30.AdmissionId = m0.AdmissionId

LEFT JOIN PrimaryDiagnonsis_CTE PD ON PD.cdpepiid = cea.EpiId

LEFT JOIN SecondaryDiagnosis_CTE SD ON SD.Cdpepiid = cea.EpiId

WHERE M0100AssmtReason IN (
'01'
,'03'
,'06'
,'07'
,'09'
)
AND cea.epiStatus NOT IN (
'DELETED'
,'PENDING'
,'NON-ADMIT'
)
AND (
YEAR(m0.M0030StartCareDt) >= YEAR(GETDATE()) - 3
OR YEAR(m0.M0906DcTranDthDt) >= YEAR(GETDATE()) - 3
)
AND CASE 
WHEN m0.M0150CPayMcareFfs = 1
THEN '1 - Medicare (traditional fee-for-service)'
WHEN m0.M0150CpayMcareHmo = 1
THEN '2 - Medicare (HMO/managed care/Advantage plan)'
WHEN m0.M0150CpayMcaidFfs = 1
THEN '3 - Medicaid (traditional fee-for-service)'
WHEN m0.M0150CpayMcaidHmo = 1
THEN '4 - Medicaid (HMO/managed care)'
ELSE 'Not Medi-Medi'
END != 'Not Medi-Medi'
