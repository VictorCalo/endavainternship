-- Toate obiectele sunt create si compilate

SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name IN ('EMPLOYEES_COPY','DEBUG_LOG', 'DEBUG_UTILS','ADJUST_SALARIES_BY_COMMISSION')
ORDER  BY object_type, object_name;

-- Asteptat: 5 randuri, toate cu status VALID

-- Resetez datele, ca sa pornim de la zero

DELETE FROM employees_copy;
DELETE FROM debug_log;

INSERT INTO employees_copy VALUES (100,'Steven','King', 24000, NULL);
INSERT INTO employees_copy VALUES (101,'Neena','Kochhar', 17000, NULL);
INSERT INTO employees_copy VALUES (103,'Alexander','Hunold', 9000, NULL);
INSERT INTO employees_copy VALUES (104,'Bruce','Ernst', 6000, NULL);
INSERT INTO employees_copy VALUES (145,'John','Russell', 14000, 0.40);
INSERT INTO employees_copy VALUES (146,'Karen','Partners', 13500, 0.30);
INSERT INTO employees_copy VALUES (150,'Peter','Tucker', 10000, 0.30);
INSERT INTO employees_copy VALUES (151,'David','Bernstein', 9500, 0.25);
INSERT INTO employees_copy VALUES (152,'Peter','Hall', 9000, 0.25);
INSERT INTO employees_copy VALUES (176,'Jonathon','Taylor', 8600, 0.20);
INSERT INTO employees_copy VALUES (200,'Jennifer','Whalen', 4400, NULL);
INSERT INTO employees_copy VALUES (201,'Michael','Hartstein', 13000, NULL);
INSERT INTO employees_copy VALUES (205,'Shelley','Higgins', 12000, NULL);
INSERT INTO employees_copy VALUES (206,'William','Gietz', 8300, NULL);
COMMIT;

-- salariile de start
SELECT employee_id, first_name, last_name, salary, commission_pct
FROM   employees_copy
ORDER  BY employee_id;

-- Asteptat: 14 angajati. King are 24000 fara comision,
-- Russell are 14000 cu comision 0.4. 


-- Cu debugul OPRIT nu se scrie nimic
BEGIN
   debug_utils.disable_debug;
   debug_utils.log_msg('mesaj de test, cu debugul oprit');
END;
/

SELECT COUNT(*) AS loguri FROM debug_log;

-- Asteptat: 0
-- Am cerut explicit o logare si tot nu s-a scris nimic.


-- Cu debugul PORNIT se logheaza fiecare pas
BEGIN
   debug_utils.enable_debug;
   debug_utils.set_log_level('DEBUG');
   adjust_salaries_by_commission;
END;
/

SELECT log_id, module_name, line_no, log_level, log_message
FROM   debug_log
ORDER  BY log_id;

-- Asteptat: ~32 de randuri - start, deschiderea cursorului,
-- pentru fiecare angajat ramura pe care a intrat + valoarea calculata,

SELECT employee_id, salary, commission_pct
FROM   employees_copy
ORDER  BY employee_id;

--  Asteptat:
-- 24000 -> 24480 (fara comision, +2%)
-- 14000 -> 19600 (cu comision 0.4, +40%)
-- 10000 -> 13000 (cu comision 0.3)

-- toate coloanele, ca sa se vada si ora si sesiunea
SELECT log_id, log_time, module_name, line_no, log_level, session_id
FROM   debug_log
ORDER  BY log_id
FETCH FIRST 5 ROWS ONLY;

-- Asteptat: log_time si session_id sunt completate automat, prin DEFAULT.
-- Nu le trimit eu la fiecare apel - retin si sesiunea curenta.


-- Filtrul de nivel 
SELECT COUNT(*) AS inainte FROM debug_log;
