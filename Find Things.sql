-- TABLE

select distinct table_schema, t.name as table_name--, c.name as column_name,data_Type

from sys.tables as t 

inner join sys.columns c on t.object_ID=c.Object_id

inner join INFORMATION_SCHEMA.COLUMNS d on d.TABLE_NAME=t.name

AND D.COLUMN_NAME=C.NAME

where t.name like '%patient%' 

order by t.name
 


-- FIELDS

select table_schema, t.name as table_name, c.name as column_name,data_Type

from sys.tables as t 

inner join sys.columns c on t.object_ID=c.Object_id

inner join INFORMATION_SCHEMA.COLUMNS d on d.TABLE_NAME=t.name

AND D.COLUMN_NAME=C.NAME

where c.name like '%non-visit%' --and table_schema = 'dbo' 

order by  t.name, C.name




-- FIND TWO FIELDS IN SAME TABLE

SELECT
    t.schema_id,
    s.name AS schema_name,
    t.name AS table_name
FROM
    sys.tables t
INNER JOIN
    sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN
    sys.columns c ON t.object_id = c.object_id
WHERE
    c.name LIKE '%payorsource%'
    OR c.name LIKE '%InsuranceType%'
GROUP BY
    t.schema_id, s.name, t.name
HAVING
    COUNT(DISTINCT CASE WHEN c.name LIKE '%payorsource%' THEN 1 END) > 0
    AND COUNT(DISTINCT CASE WHEN c.name LIKE '%insurancetype%' THEN 1 END) > 0
ORDER BY
    s.name, t.name;


 
 
select distinct PendingReason from th.Referrals	(nolock)
 
--select distinct ReferralStatus from factreferral -- statusReason
 
--select distinct ReferralRejectedReason  from th.dimReferral
 
 
--views w/ col

select v.name as view_name, c.name as column_name

from sys.views as v 

inner join sys.columns c on v.object_ID=c.Object_id

where c.name like '%reason%' --or v.name like '%fire%'

order by v.name
 
 
 
--find sps updating a table

select distinct o.name, o.xtype from 

syscomments c 

inner join sysobjects o on c.id=o.id

where c.text like '%reason%'


select @@VERSION

 