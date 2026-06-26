SELECT * FROM cohort_users_raw 
LIMIT 10; 
SELECT * FROM cohort_events_raw 
LIMIT 10; 
--Починаємо з таблиці cohort_users_raw, розбиваємо запит на кілька частин
--Прибираємо пробіли та беремо лише частину до першого пробілу (саму дату)
select  
split_part(trim(signup_datetime), ' ',1) as clean_date
from cohort_users_raw;
--Обгортаємо попередню формулу у replace, міняємо крапки на тире, слеші на тире
select 
replace(replace(clean_date,'.','-'),'/','-') as uni_date 
from
(select split_part(trim(signup_datetime), ' ',1) as clean_date
from cohort_users_raw) as inter_table;
--lдодаємо case для перевірки формату дат
select uni_date,
case 
	when uni_date like '____-__-__' then 'ISO'
	when uni_date like '__-__-____' then 'DMY'
	else 'Unknown'
end as date_format
from (select 
replace(replace(clean_date,'.','-'),'/','-') as uni_date 
from
(select split_part(trim(signup_datetime), ' ',1) as clean_date
from cohort_users_raw) as step1)as step2;
--додаємо timestamp
select uni_date,
case 
	when uni_date like '____-__-__' then to_date(uni_date, 'YYYY-MM-DD')
	when uni_date like '__-__-____' then to_date(uni_date, 'DD-MM-YYYY')
	else null
end::timestamp as signup_date
from (select 
replace(replace(clean_date,'.','-'),'/','-') as uni_date 
from
(select split_part(trim(signup_datetime), ' ',1) as clean_date
from cohort_users_raw) as step1)as step2;
--перетворення дати у cohort_users_raw
WITH cleaned_data AS (
        SELECT *, 
        REPLACE(REPLACE(SPLIT_PART(TRIM(signup_datetime), ' ', 1), '.', '-'), '/', '-') AS uni_date
    FROM cohort_users_raw),
converted_data AS (
        SELECT *,
        CASE 
            WHEN uni_date ~ '^\d{4}-\d{1,2}-\d{1,2}' 
            THEN TO_DATE(uni_date, 'YYYY-MM-DD')
            WHEN uni_date ~ '^\d{1,2}-\d{1,2}-\d{4}' 
            THEN TO_DATE(uni_date, 'DD-MM-YYYY')           
            WHEN uni_date ~ '^\d{1,2}-\d{1,2}-\d{2}$' 
            THEN TO_DATE(uni_date, 'DD-MM-YY')
            ELSE NULL 
        END::timestamp AS signup_date_clean
    FROM cleaned_data)
SELECT * FROM converted_data;

--перетворення дати у cohort_events_raw, той самий код, але для іншої таблиці
WITH cleaned_data AS (
        SELECT *, 
        REPLACE(REPLACE(SPLIT_PART(TRIM(event_datetime), ' ', 1), '.', '-'), '/', '-') AS uni_date
    FROM cohort_events_raw),
converted_data AS (
        SELECT *,
        CASE 
            WHEN uni_date ~ '^\d{4}-\d{1,2}-\d{1,2}' 
            THEN TO_DATE(uni_date, 'YYYY-MM-DD')
            WHEN uni_date ~ '^\d{1,2}-\d{1,2}-\d{4}' 
            THEN TO_DATE(uni_date, 'DD-MM-YYYY')           
            WHEN uni_date ~ '^\d{1,2}-\d{1,2}-\d{2}$' 
            THEN TO_DATE(uni_date, 'DD-MM-YY')
            ELSE NULL 
        END::timestamp AS event_date_clean
    FROM cleaned_data)
SELECT * FROM converted_data;
--об'єднання двох CTE через left join по стовпчику user_id.Left Join залишить усіх зареєстрованих користувачів 
--(з першої таблиці) і додасть до них події, якщо вони були
WITH users_cleaned AS (
    -- Очищення першої таблиці (користувачі)
    SELECT *,
        CASE 
            WHEN uni_date ~ '^\d{4}-\d{1,2}-\d{1,2}' THEN TO_DATE(uni_date, 'YYYY-MM-DD')
            WHEN uni_date ~ '^\d{1,2}-\d{1,2}-\d{4}' THEN TO_DATE(uni_date, 'DD-MM-YYYY')           
            WHEN uni_date ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN TO_DATE(uni_date, 'DD-MM-YY')
            ELSE NULL 
        END::timestamp AS signup_date_clean
    FROM (
        SELECT *, REPLACE(REPLACE(SPLIT_PART(TRIM(signup_datetime), ' ', 1), '.', '-'), '/', '-') AS uni_date
        FROM cohort_users_raw
    ) AS sub
),
events_cleaned AS (
    -- Очищення другої таблиці (події)
    SELECT *,
        CASE 
            WHEN uni_date ~ '^\d{4}-\d{1,2}-\d{1,2}' THEN TO_DATE(uni_date, 'YYYY-MM-DD')
            WHEN uni_date ~ '^\d{1,2}-\d{1,2}-\d{4}' THEN TO_DATE(uni_date, 'DD-MM-YYYY')           
            WHEN uni_date ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN TO_DATE(uni_date, 'DD-MM-YY')
            ELSE NULL 
        END::timestamp AS event_date_clean
    FROM (
        SELECT *, REPLACE(REPLACE(SPLIT_PART(TRIM(event_datetime), ' ', 1), '.', '-'), '/', '-') AS uni_date
        FROM cohort_events_raw
    ) AS sub
)
SELECT u.promo_signup_flag,
-- Створення поля когорти (місяць реєстрації)
   date_trunc('month', u.signup_date_clean)::date as cohort_month,
    --e.event_date_clean,
    -- Розрахунок різниці в місяцях
    (EXTRACT(year FROM e.event_date_clean) - EXTRACT(year FROM u.signup_date_clean)) * 12 +
    (EXTRACT(month FROM e.event_date_clean) - EXTRACT(month FROM u.signup_date_clean)) AS month_offset,
    --e.event_type,
    --e.revenue,
    COUNT(DISTINCT u.user_id) AS users_total
FROM users_cleaned u
LEFT JOIN events_cleaned e ON u.user_id = e.user_id
--фільтрація через where
WHERE 
    u.signup_date_clean IS NOT NULL        
    AND e.event_date_clean IS NOT NULL      
    AND e.event_type IS NOT NULL            
    AND e.event_type != 'test_event'
    -- фільтрація періоду активності: січень - червень 2025
    AND e.event_date_clean >= '2025-01-01' 
    AND e.event_date_clean < '2025-07-01'
GROUP by u.promo_signup_flag, cohort_month, month_offset
ORDER BY 1, 2, 3;
