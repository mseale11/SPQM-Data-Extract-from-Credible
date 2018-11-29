-- -------------------------------------------------------------------------------------------------
--  Report Name:  SPQM Data Extract from Credible
--
--        Notes:  Flat file should be submitted as TAB delimited, ASCII text and should represent all 
--                encounters recorded in the transaction system for a full month.
--                SPQM recommends submitting the Field/Column Names as the first row of data submitted if possible.
--                Please note that the column ordering, including empty columns/placeholders for missing data is essential.
--                Raw data file naming convention:  ShortOrgName followed by Month(s) and Year represented in file.
--                Example  CMHC 07-2018.txt   or CMHC 1-7 2018.txt
--                Please direct any questions to rlove@intelliprocess.com or (512) 420-8110
--
--      Updates:  11/02/2018 - Created by Monica Seale (monica.seale@regionten.org) at Region Ten CSB.
--                11/14/2018 - 1)  COMP (Agency Code) is no longer hard coded.  It's now looked up in the PartnerConfig table.
--                             2)  Replaced DSM-5 Code with ICD-10 Code for DX1 - DX8 (diagnoses).
-- -------------------------------------------------------------------------------------------------
SET NOCOUNT ON

-- Must DECLARE @param1 and @param2 if using Credible BI.
DECLARE @param1 date = {?} -- Start Date
DECLARE @param2 date = {?} -- End Date


-- Build list of consumers with open 920 Type of Care/Episode in report period.
DECLARE @toc_920 TABLE (client_id int)

INSERT INTO @toc_920 (client_id)

SELECT DISTINCT ce1.client_id
FROM ClientEpisode ce1
INNER JOIN Clients c2 ON c2.client_id = ce1.client_id
INNER JOIN Programs p2 ON p2.program_id = ce1.program_id
WHERE p2.export_program_code = '920' -- Medicaid Developmental Disability (DD) Home and Community-Based Waiver Services
AND p2.deleted = 0
AND COALESCE(ce1.discharge_date, ce1.date_closed_auto, '2079-01-01') >= @param1
AND CONVERT(date, COALESCE(ce1.admission_date, ce1.date_created)) <= @param2
-- Exclude test and deleted consumers.
AND COALESCE(c2.external_id, CONVERT(varchar(10), c2.client_id)) <> 'ZEXCLUDE'
AND c2.deleted = 0


-- Build list of consumers with open 923 Type of Care/Episode in report period.
DECLARE @toc_923 TABLE (client_id int)

INSERT INTO @toc_923 (client_id)

SELECT DISTINCT ce2.client_id
FROM ClientEpisode ce2
INNER JOIN Clients c3 ON c3.client_id = ce2.client_id
INNER JOIN Programs p3 ON p3.program_id = ce2.program_id
WHERE p3.export_program_code = '923' -- Developmental Enhanced Case Management Services
AND p3.deleted = 0
AND COALESCE(ce2.discharge_date, ce2.date_closed_auto, '2079-01-01') >= @param1
AND CONVERT(date, COALESCE(ce2.admission_date, ce2.date_created)) <= @param2
-- Exclude test and deleted consumers.
AND COALESCE(c3.external_id, CONVERT(varchar(10), c3.client_id)) <> 'ZEXCLUDE'
AND c3.deleted = 0


-- Generate data extract.
SELECT COALESCE((SELECT LTRIM(RTRIM(pc1.paramvalue))
FROM PartnerConfig pc1
WHERE pc1.parameter = 'partnercode'), '') AS [COMP]
-- CASE is a Microsoft SQL Server reserved keyword.
-- Include external_id?
, CONVERT(varchar(10), cv1.client_id) AS [CASE]
-- PLACEHOLDER ONLY.  Do not populate until further notice.
, '' AS [AlternateID]
, CONVERT(varchar(10), c1.dob, 101) AS [DOB]
, (CASE c1.sex
WHEN 'F' THEN '01' -- Female
WHEN 'M' THEN '02' -- Male
ELSE '98' -- Not Collected (Not asked)
END) AS [Gender]
, p1.export_program_code AS [DIV]
, CONVERT(varchar(10), cv1.program_id) AS [UNITNo]
, p1.program_desc AS [UNIT]
, '' AS [SUBUNITNo]
, '' AS [SUBUNIT]
-- Include external_id?
, CONVERT(varchar(10), cv1.emp_id) AS [SERVER]
, e1.last_name AS [LAST]
, e1.first_name AS [FIRST]
, e1.credentials AS [STAFFTYPE]
-- Use clientvisit_id instead?
, CONVERT(varchar(10), cv1.visittype_id) AS [SVCODE]
, vt1.description AS [SERVICE]
, CONVERT(varchar(10), cv1.rev_timein, 101) AS [DATE]
, CONVERT(varchar(5), cv1.rev_timein, 114) AS [START]
, CONVERT(varchar(5), cv1.rev_timeout, 114) AS [STOP]
, CONVERT(varchar(10), cv1.duration) AS [CLIENTIME]
-- Does lookup table exist in Credible?
-- Modify to use Cancellation/No-Show form.
, (CASE pl1.visit_status
WHEN 'ARRIVED' THEN '01'
WHEN 'CANCELLED' THEN '02'
WHEN 'CNCLD BY PROV' THEN '03'
WHEN 'CNCLD>24hr' THEN '04'
WHEN 'COMPLETED' THEN '05'
WHEN 'EMERGENCY' THEN '06'
WHEN 'NON-CLIENT' THEN '07'
WHEN 'NOSHOW' THEN '08'
WHEN 'NOTPRESENT' THEN '09'
WHEN 'RESCHEDULE' THEN '10'
WHEN 'SCHEDULED' THEN '11'
WHEN 'WALK-IN' THEN '12'
ELSE ''
END) AS [APPT]
, pl1.visit_status AS [APPOINTMENT]
,(CASE WHEN (SELECT COUNT(*) 
FROM ClientInsurance ci1
INNER JOIN Payer pa2 ON pa2.payer_id = ci1.payer_id
INNER JOIN Z_PayerType pt2 ON pt2.payertype_id = pa2.payertype_id
WHERE ci1.client_id = cv1.client_id
AND pt2.payertype_code IN ('03', '10', '11', '12') -- Medicaid, Medicaid Managed Care, Medicare Medicaid Duel Eligible, Medicaid Governor's Access Plan (GAP)
AND (CONVERT(date, ci1.start_date) <= @param2 AND (ci1.end_date IS NULL OR CONVERT(date, ci1.end_date) >= @param1))
AND ci1.deleted = 0) = 0
THEN 'N' -- No
ELSE 'Y' -- Yes
END) AS [MDCD]
, cv1.cptcode AS [CPT]
, (CASE WHEN pt1.payertype_code IS NOT NULL
THEN pt1.payertype_code
WHEN cv1.non_billable = 1
THEN '96' -- Not Applicable
ELSE '98' -- Not Collected (Not asked)
END) AS [PAYORBILLED]
, (SELECT TOP(1) e2.last_name + ', ' + e2.first_name AS emp_name
FROM EmployeeSupervisor es1
INNER JOIN Employees e2 ON e2.emp_id = es1.supervisor_emp_id
WHERE es1.emp_id = e1.emp_id
AND es1.is_indirect = 0
ORDER BY e2.last_name + ', ' + e2.first_name ASC) AS [SUPERVISOR]
-- DSM-5 Code = axis_code
-- ICD-10 Code = icd10_code
, REPLACE(cv1.icd10_code, '.', '') AS [DX1]
, REPLACE(cv1.icd10_code2, '.', '') AS [DX2]
, REPLACE(cv1.icd10_code3, '.', '') AS [DX3]
, REPLACE(cv1.icd10_code4, '.', '') AS [DX4]
, REPLACE(cv1.icd10_code5, '.', '') AS [DX5]
, '' AS [DX6]
, '' AS [DX7]
, '' AS [DX8]
, (CASE WHEN cv1.client_id IN (SELECT * FROM @toc_923)
THEN 'Y' -- Yes - Meets Criteria for ECM
WHEN cv1.client_id IN (SELECT * FROM @toc_920)
THEN 'N' -- No - Does NOT meet Criteria for ECM
ELSE 'A' -- Not Applicable
END) AS [EnhancedCM]

FROM ClientVisit cv1
INNER JOIN Clients c1 ON c1.client_id = cv1.client_id
INNER JOIN Employees e1 ON e1.emp_id = cv1.emp_id
INNER JOIN Programs p1 ON p1.program_id = cv1.program_id
INNER JOIN VisitType vt1 ON vt1.visittype_id = cv1.visittype_id
INNER JOIN ClientVisitBilling cvb1 ON cvb1.clientvisit_id = cv1.clientvisit_id
LEFT OUTER JOIN Payer pa1 ON pa1.payer_id = cvb1.pri_payer_id -- Primary Payer
LEFT OUTER JOIN Z_PayerType pt1 ON pt1.payertype_id = pa1.payertype_id
LEFT OUTER JOIN Planner pl1 ON pl1.plan_id = cv1.plan_id

WHERE (cv1.rev_timein >= @param1 AND cv1.rev_timein < DATEADD(day, 1, @param2))
-- Exclude test and deleted consumers.
AND COALESCE(c1.external_id, CONVERT(varchar(10), c1.client_id)) <> 'ZEXCLUDE'
AND c1.deleted = 0
