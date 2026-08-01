-- ====================================================================
-- ORDS REST Handler Update for GET /MyEmployees/Present
-- Date: 12-07-2026
-- Description:
--   Updates the GET /MyEmployees/Present handler to load subordinates
--   either using the hierarchy or custom department exceptions.
-- ====================================================================

DECLARE
  l_source CLOB;
BEGIN
  -- We wrap the source in a CLOB to avoid single-quote escaping issues
  l_source := 
'DECLARE
    l_header_value    VARCHAR2(4000);
    l_bearer_token    VARCHAR2(4000);
    l_token           APEX_JWT.T_TOKEN;
    l_user_object     APEX_JSON.T_VALUES;
    l_user_id         NUMBER;
    l_user_type       VARCHAR2(200);
    l_iss             VARCHAR2(200);

    l_employee_id     NUMBER;
    l_date_filter     DATE;
    l_total           NUMBER := 0;
    l_sub_source      VARCHAR2(20);

BEGIN
    -- ===== 1. TOKEN VALIDATION =====
    l_header_value := OWA_UTIL.get_cgi_env(''Authorization'');

    IF l_header_value IS NULL OR INSTR(l_header_value, ''Bearer '') != 1 THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                  p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''يرجى تسجيل الدخول أولاً'', p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''Authentication required'', p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''TOKEN_REQUIRED'',         p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := ' || '401;
        RETURN;
    END IF;

    l_bearer_token := SUBSTR(l_header_value, 8);

    BEGIN
        l_token := APEX_JWT.DECODE(
            p_value         => l_bearer_token,
            p_signature_key => SYS.UTL_RAW.CAST_TO_RAW(''secretKey'')
        );
        APEX_JSON.PARSE(l_user_object, l_token.payload);

        IF NOT APEX_JSON.DOES_EXIST(p_path => ''sub'', p_values => l_user_object) THEN
            APEX_JSON.open_object;
            APEX_JSON.write(''status'',    ''error'',          p_write_null => TRUE);
            APEX_JSON.write(''messageAr'', ''Token غير صالح'', p_write_null => TRUE);
            APEX_JSON.write(''messageEn'', ''Invalid token'',  p_write_null => TRUE);
            APEX_JSON.write(''errorCode'', ''INVALID_TOKEN'',  p_write_null => TRUE);
            APEX_JSON.close_object;
            :status := 401;
            RETURN;
        END IF;

        l_iss := APEX_JSON.GET_VARCHAR2(p_path => ''iss'', p_values => l_user_object);

        IF l_iss IS NULL ' || 'OR l_iss != ''ORDS'' THEN
            APEX_JSON.open_object;
            APEX_JSON.write(''status'',    ''error'',          p_write_null => TRUE);
            APEX_JSON.write(''messageAr'', ''Token غير صالح'', p_write_null => TRUE);
            APEX_JSON.write(''messageEn'', ''Invalid token'',  p_write_null => TRUE);
            APEX_JSON.write(''errorCode'', ''INVALID_TOKEN'',  p_write_null => TRUE);
            APEX_JSON.close_object;
            :status := 401;
            RETURN;
        END IF;

        l_user_id   := TO_NUMBER(APEX_JSON.GET_VARCHAR2(p_path => ''sub'', p_values => l_user_object));
        l_user_type :=           APEX_JSON.GET_VARCHAR2(p_path => ''aud'', p_values => l_user_object);

    EXCEPTION
        WHEN OTHERS THEN
            APEX_JSON.open_object;
            APEX_JSON.write(''status'',    ''error'',          p_write_null => TRUE);
            APEX_JSON.write(''messageAr'', ''Token غير صالح'', p_write_null => TRUE);
            APEX_JSON.write(''messageEn'', ''Invalid t' || 'oken'',  p_write_null => TRUE);
            APEX_JSON.write(''errorCode'', ''INVALID_TOKEN'',  p_write_null => TRUE);
            APEX_JSON.close_object;
            :status := 401;
            RETURN;
    END;

    -- ===== 2. GET EMPLOYEE_ID (المدير) =====
    BEGIN
        SELECT E.EMPLOYEE_ID, NVL(E.SUBORDINATE_SOURCE, ''STRUCTURE'')
        INTO   l_employee_id, l_sub_source
        FROM   SEC_USERS U
        JOIN   HR_EMPLOYEES E
            ON U.USER_TYPE    = ''EMPLOYEE''
            AND E.EMPLOYEE_ID = U.REFERENCE_USER_ID
        WHERE  U.ID = l_user_id
        AND    ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            APEX_JSON.open_object;
            APEX_JSON.write(''status'',    ''error'',                          p_write_null => TRUE);
            APEX_JSON.write(''messageAr'', ''المستخدم غير مرتبط بموظف'',       p_write_null => TRUE);
            APEX_JSON.write(''messageEn'', ''User is not linked to employee'', p_write_null => TRUE);
            APEX_JSON.write(''errorCode'', ''EMPLOYEE_NOT_LINKED'',      ' || '      p_write_null => TRUE);
            APEX_JSON.close_object;
            :status := 400;
            RETURN;
    END;

    -- ===== 3. READ QUERY PARAMS =====
    l_date_filter := NVL(
        TO_DATE(:date_filter, ''DD-MM-YYYY''),
        TRUNC(SYSDATE)
    );

    -- ===== 4. GET TOTAL COUNT =====
    SELECT COUNT(*) INTO l_total
    FROM HR_EMPLOYEES E
    JOIN (
        SELECT D.ID AS DEPT_ID
        FROM   HR_DEPARTMENT D
        WHERE  l_sub_source = ''STRUCTURE''
        START WITH D.MANAGER_ID = l_employee_id
        CONNECT BY PRIOR D.ID   = D.PARENT_ID
        
        UNION ALL
        
        SELECT D2.ID AS DEPT_ID
        FROM   HR_DEPARTMENT D2
        START WITH D2.ID IN (
            SELECT EX.DEPARTMENT_ID
            FROM   HR_MANAGER_DEPT_EXCEPTIONS EX
            WHERE  EX.EMPLOYEE_ID = l_employee_id
            AND    EX.STATUS = ''1''
            AND    l_sub_source = ''EXCEPTIONS''
        )
        CONNECT BY PRIOR D2.ID = D2.PARENT_ID
    ) DEPT_HIER ON DEPT_HIER.DEPT_ID = E.DEPARTMENT_ID
    WHERE E.STATUS = 1; -- الفلترة بحالة الموظف (تم إلغاء استثناء المدير)

    -- ===== 5. SUCCESS RESPONSE =====
    :status := 200;
    APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''success'',                     p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''تم جلب بيانات الحضور بنجاح'',  p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''Attendanc' || 'e retrieved successfully'', p_write_null => TRUE);
        APEX_JSON.write(''date'',      TO_CHAR(l_date_filter, ''DD/MM/YYYY''), p_write_null => TRUE);
        APEX_JSON.write(''total'',     l_total,                        p_write_null => TRUE);

        APEX_JSON.open_array(''attendance'');

        FOR rec IN (
            SELECT
                E.EMPLOYEE_ID,
                E.CODE                  AS EMPLOYEE_CODE,
                E.FULL_NAME_AR,
                E.FULL_NAME_EN,
                DEPT_HIER.DEPT_NAME     AS DEPARTMENT_NAME,

                TO_CHAR(A.CHECK_IN_TIME,  ''HH12:MI PM'')  AS CHECK_IN_TIME,
                CASE WHEN A.HAS_OUT = 1
                     THEN TO_CHAR(A.CHECK_OUT_TIME, ''HH12:MI PM'')
                END                                       AS CHECK_OUT_TIME,
                CASE WHEN A.HAS_OUT = 1
                     THEN ROUND((A.CHECK_OUT_TIME - A.CHECK_IN_TIME) * 24, 2)
                END                                       AS WOR' || 'KING_HOURS,

                -- ===== ATTENDANCE STATUS =====
                CASE
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND CTO.EMPLOYEE_ID IS NOT NULL 
                        THEN ''COMPLETE_CTO''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND OT.EMPLOYEE_ID IS NOT NULL 
                        THEN ''COMPLETE_OVERTIME''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''PERMISSION''
                        THEN ''COMPLETE_PERMISSION''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''RECALL''
                        THEN ''COMPLETE_RECALL''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 
                        THEN ''COMPLETE''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 AND CTO.EMPLOYEE_ID IS NOT NULL 
                        THEN ''NO_CHECKOUT_CTO''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT' || ',0) = 0 AND OT.EMPLOYEE_ID IS NOT NULL 
                        THEN ''NO_CHECKOUT_OVERTIME''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''PERMISSION''
                        THEN ''NO_CHECKOUT_PERMISSION''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''RECALL''
                        THEN ''NO_CHECKOUT_RECALL''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 
                        THEN ''NO_CHECKOUT''
                    WHEN LV.EMPLOYEE_ID IS NOT NULL 
                        THEN ''LEAVE''
                    WHEN MS.EMPLOYEE_ID IS NOT NULL 
                        THEN ''MISSION''
                    WHEN WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''PERMISSION''
                        THEN ''ABSENT_PERMISSION''
                    WHEN WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''RECALL''
                        THEN ''A' || 'BSENT_RECALL''
                    WHEN AB.EMPLOYEE_ID IS NOT NULL 
                        THEN ''ABSENT''
                    WHEN PH.EMPLOYEE_ID IS NOT NULL 
                        THEN ''PUBLIC_HOLIDAY''
                    WHEN CD.EMPLOYEE_ID IS NOT NULL 
                        THEN ''COMPENSATORY''
                    WHEN WO.EMPLOYEE_ID IS NOT NULL 
                        THEN ''WEEKLY_OFF''
                    ELSE ''NOT_PRESENT''
                END AS ATTENDANCE_STATUS,

                -- ===== STATUS AR =====
                CASE
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND CTO.EMPLOYEE_ID IS NOT NULL 
                        THEN ''حاضر - مكتمل (بدل يعوض)''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND OT.EMPLOYEE_ID IS NOT NULL 
                        THEN ''حاضر - مكتمل (إضافي أجر)''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''PERMISSION''
                        THEN ''حا' || 'ضر - مكتمل (استئذان)''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''RECALL''
                        THEN ''حاضر - مكتمل (استدعاء)''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 
                        THEN ''حاضر - مكتمل''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 AND CTO.EMPLOYEE_ID IS NOT NULL 
                        THEN ''حاضر - بدل يعوض''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 AND OT.EMPLOYEE_ID IS NOT NULL 
                        THEN ''حاضر - إضافي أجر''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''PERMISSION''
                        THEN ''حاضر - استئذان''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''RECALL''
                        THEN ''حاضر - استدعاء''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 ' || '
                        THEN ''حاضر - لم ينصرف''
                    WHEN LV.EMPLOYEE_ID IS NOT NULL 
                        THEN ''إجازة - '' || LV.LEAVE_TYPE_AR
                    WHEN MS.EMPLOYEE_ID IS NOT NULL 
                        THEN ''مهمة عمل''
                    WHEN WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''PERMISSION''
                        THEN ''غياب - استئذان''
                    WHEN WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''RECALL''
                        THEN ''غياب - استدعاء''
                    WHEN AB.EMPLOYEE_ID IS NOT NULL 
                        THEN ''غياب مسجل''
                    WHEN PH.EMPLOYEE_ID IS NOT NULL 
                        THEN ''عطلة رسمية''
                    WHEN CD.EMPLOYEE_ID IS NOT NULL 
                        THEN ''راحة مستحقة''
                    WHEN WO.EMPLOYEE_ID IS NOT NULL 
                        THEN ''راحة أسبوعية''
                    ELSE ''لم يحضر''
                END AS STATUS_AR,

             ' || '   -- ===== STATUS EN =====
                CASE
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND CTO.EMPLOYEE_ID IS NOT NULL 
                        THEN ''Present - Complete (CTO)''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND OT.EMPLOYEE_ID IS NOT NULL 
                        THEN ''Present - Complete (Overtime)''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''PERMISSION''
                        THEN ''Present - Complete (Permission)''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''RECALL''
                        THEN ''Present - Complete (Recall)''
                    WHEN A.HAS_IN = 1 AND A.HAS_OUT = 1 
                        THEN ''Present - Complete''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 AND CTO.EMPLOYEE_ID IS NOT NULL 
                        THEN ''Present - CTO''
                    WHEN A.HAS_IN =' || ' 1 AND NVL(A.HAS_OUT,0) = 0 AND OT.EMPLOYEE_ID IS NOT NULL 
                        THEN ''Present - Overtime''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''PERMISSION''
                        THEN ''Present - Permission''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 AND WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''RECALL''
                        THEN ''Present - Recall''
                    WHEN A.HAS_IN = 1 AND NVL(A.HAS_OUT,0) = 0 
                        THEN ''Present - No Check Out''
                    WHEN LV.EMPLOYEE_ID IS NOT NULL 
                        THEN ''Leave - '' || LV.LEAVE_TYPE_EN
                    WHEN MS.EMPLOYEE_ID IS NOT NULL 
                        THEN ''Work Mission''
                    WHEN WP.EMPLOYEE_ID IS NOT NULL AND WP.PERMIT_TYPE = ''PERMISSION''
                        THEN ''Absent - Permission''
                    WHEN WP.EMPLOYEE_ID IS NOT NULL AND WP.' || 'PERMIT_TYPE = ''RECALL''
                        THEN ''Absent - Recall''
                    WHEN AB.EMPLOYEE_ID IS NOT NULL 
                        THEN ''Registered Absence''
                    WHEN PH.EMPLOYEE_ID IS NOT NULL 
                        THEN ''Public Holiday''
                    WHEN CD.EMPLOYEE_ID IS NOT NULL 
                        THEN ''Compensatory Day''
                    WHEN WO.EMPLOYEE_ID IS NOT NULL 
                        THEN ''Weekly Off''
                    ELSE ''Not Present''
                END AS STATUS_EN,

                -- ===== IS DISABLED ACTION =====
                CASE
                    WHEN CTO.EMPLOYEE_ID IS NOT NULL THEN 1
                    WHEN OT.EMPLOYEE_ID IS NOT NULL THEN 1
                    WHEN WP.EMPLOYEE_ID IS NOT NULL THEN 1
                    WHEN MS.EMPLOYEE_ID IS NOT NULL THEN 1
                    WHEN AB.EMPLOYEE_ID IS NOT NULL THEN 1
                    -- Leaves, Holiday, Weekly Off, Compensatory days D' || 'O NOT disable actions
                    ELSE 0
                END AS IS_DISABLED_ACTION,

                -- ===== CTO DETAILS =====
                CTO.CTO_ID,
                CTO.CTO_HOURS,

                -- ===== OVERTIME DETAILS =====
                OT.OT_ID,
                OT.OT_FROM_TIME,
                OT.OT_TO_TIME

            FROM HR_EMPLOYEES E

            -- ── الأقسام تحت المدير ──
            JOIN (
                SELECT D.ID           AS DEPT_ID,
                       D.ARABIC_NAME  AS DEPT_NAME
                FROM   HR_DEPARTMENT D
                WHERE  l_sub_source = ''STRUCTURE''
                START WITH D.MANAGER_ID = l_employee_id
                CONNECT BY PRIOR D.ID   = D.PARENT_ID
                
                UNION ALL
                
                SELECT D2.ID          AS DEPT_ID,
                       D2.ARABIC_NAME AS DEPT_NAME
                FROM   HR_DEPARTMENT D2
                START WITH D2.ID IN (
                    SELECT EX.DEPARTMENT_ID
                    FROM   HR_MANAGER_DEPT_EXCEPTIONS EX
                    WHERE  EX.EMPLOYEE_ID = l_employee_id
                    AND    EX.STATUS = ''1''
                    AND    l_sub_source = ''EXCEPTIONS''
                )
                CONNECT BY PRIOR D2.ID = D2.PARENT_ID
            ) DEPT_HIER ON DEPT_HIER.DEPT_ID = E.DEPARTMENT_ID

            -- ── بيانات الحضور ──
            LEFT JOIN (
                SELECT EMPLOYEE_ID, HAS_IN, HAS_OUT,
                       CHECK_IN_TIME, CHECK_OUT_TIME
                FROM   VW_ATTENDANCE_LOG
                WHERE  TR' || 'UNC(ATTENDANCE_DATE) = TRUNC(l_date_filter)
            ) A ON A.EMPLOYEE_ID = E.EMPLOYEE_ID

            -- ── بدل يعوض ──
            LEFT JOIN (
                SELECT EMPLOYEE_ID,
                       ID AS CTO_ID,
                       CTO_HOURS
                FROM   HR_CTO_TRANSACTIONS
                WHERE  STATUS = 1
                AND    TRUNC(CTO_DATE) = TRUNC(l_date_filter)
            ) CTO ON CTO.EMPLOYEE_ID = E.EMPLOYEE_ID

            -- ── إضافي أجر ──
            LEFT JOIN (
                SELECT EMPLOYEE_ID,
                       ID AS OT_ID,
                       FROM_TIME AS OT_FROM_TIME,
                       TO_TIME AS OT_TO_TIME
                FROM   HR_OVERTIME_REQUESTS
                WHERE  STATUS = ''1''
                AND    TRUNC(OVERTIME_DATE) = TRUNC(l_date_filter)
            ) OT ON OT.EMPLOYEE_ID = E.EMPLOYEE_ID

            -- ── تصريح عمل (استئذان أو استدعاء) ──
            LEFT JOIN (
                SELECT EMPLOYE' || 'E_ID, PERMIT_TYPE
                FROM   HR_WORK_PERMITS
                WHERE  STATUS = 1 
                AND    TRUNC(PERMIT_DATE) = TRUNC(l_date_filter)
            ) WP ON WP.EMPLOYEE_ID = E.EMPLOYEE_ID

            -- ── مهمة عمل ──
            LEFT JOIN (
                SELECT EMPLOYEE_ID
                FROM   HR_EMPLOYEE_MISSIONS
                WHERE  STATUS_ID IN (1, 4)
                AND    TRUNC(l_date_filter) BETWEEN TRUNC(START_DATE) AND TRUNC(NVL(END_DATE, START_DATE))
            ) MS ON MS.EMPLOYEE_ID = E.EMPLOYEE_ID

            -- ── بيانات الإجازة ──
            LEFT JOIN (
                SELECT LR.EMPLOYEE_ID,
                       LT.ARABIC_NAME  AS LEAVE_TYPE_AR,
                       LT.NAME         AS LEAVE_TYPE_EN
                FROM   HR_EMPLOYEE_LEAVE_REQUESTS LR
                JOIN   HR_LEAVE_TYPES LT ON LT.ID = LR.LEAVE_TYPE_ID
                WHERE  LR.STATUS_ID = 4
                AND    TRUNC(l_date_filter) BETWEEN TRUNC(LR' || '.START_DATE) AND TRUNC(LR.END_DATE)
            ) LV ON LV.EMPLOYEE_ID = E.EMPLOYEE_ID

            -- ── بيانات الغياب ──
            LEFT JOIN (
                SELECT EMPLOYEE_ID
                FROM   HR_ABSENCE_LOG
                WHERE  STATUS = ''1''
                AND    TRUNC(l_date_filter) BETWEEN TRUNC(ABSENCE_DATE) AND TRUNC(NVL(END_DATE, ABSENCE_DATE))
            ) AB ON AB.EMPLOYEE_ID = E.EMPLOYEE_ID

            -- ── عطلة رسمية ──
            LEFT JOIN (
                SELECT E2.EMPLOYEE_ID
                FROM   HR_EMPLOYEES E2
                JOIN   HR_OFFICIAL_HOLIDAYS H
                    ON  TRUNC(H.HOLIDAY_DATE) = TRUNC(l_date_filter)
                    AND H.STATUS = 1
                    AND (H.RELIGION_ID IS NULL OR H.RELIGION_ID = E2.RELIGION)
                    AND (H.SHIFT_ID IS NULL OR H.SHIFT_ID = E2.WORK_SHIFT_ID)
            ) PH ON PH.EMPLOYEE_ID = E.EMPLOYEE_ID

            -- ── راحة مستحقة ──
            LEFT JOIN (
      ' || '          SELECT E2.EMPLOYEE_ID
                FROM   HR_EMPLOYEES E2
                JOIN   VW_SHIFT_COMPENSATORY_DAYS CD2
                    ON  CD2.WORK_SHIFT_ID = E2.WORK_SHIFT_ID
                    AND TRUNC(CD2.COMP_DATE) = TRUNC(l_date_filter)
            ) CD ON CD.EMPLOYEE_ID = E.EMPLOYEE_ID

            -- ── راحة أسبوعية ──
            LEFT JOIN (
                SELECT DISTINCT E3.EMPLOYEE_ID
                FROM   HR_EMPLOYEES E3
                JOIN   HR_WORK_SHIF_DAYS SD
                    ON  SD.SHIFT_ID = E3.WORK_SHIFT_ID
                    AND SD.IS_OFF = 1
                    AND SD.DAY_ID = MOD(
                            TRUNC(l_date_filter) - (
                                SELECT TRUNC(WEEK_REF_DATE)
                                FROM   SYSTEM_SETTINGS
                                WHERE  ROWNUM = 1
                            ), 7) + 1
            ) WO ON WO.EMPLOYEE_ID = E.EMPLOYEE_ID

            WHERE E.STATUS = 1 -- الفلترة ' || 'بحالة الموظف (تم إلغاء استثناء المدير)
            ORDER BY DEPT_HIER.DEPT_NAME, E.FULL_NAME_AR
        ) LOOP
            APEX_JSON.open_object;
                APEX_JSON.write(''employeeId'',        rec.EMPLOYEE_ID,        p_write_null => TRUE);
                APEX_JSON.write(''employeeCode'',      rec.EMPLOYEE_CODE,      p_write_null => TRUE);
                APEX_JSON.write(''nameAr'',            rec.FULL_NAME_AR,       p_write_null => TRUE);
                APEX_JSON.write(''nameEn'',            rec.FULL_NAME_EN,       p_write_null => TRUE);
                APEX_JSON.write(''departmentName'',    rec.DEPARTMENT_NAME,    p_write_null => TRUE);
                APEX_JSON.write(''checkInTime'',       rec.CHECK_IN_TIME,      p_write_null => TRUE);
                APEX_JSON.write(''checkOutTime'',      rec.CHECK_OUT_TIME,     p_write_null => TRUE);
                APEX_JSON.write(''workingHours'',      rec.WORKING_HOURS,      p_write_null => TRUE);
                APEX_JSON.write(''attendanc' || 'eStatus'',  rec.ATTENDANCE_STATUS,  p_write_null => TRUE);
                APEX_JSON.write(''statusAr'',          rec.STATUS_AR,          p_write_null => TRUE);
                APEX_JSON.write(''statusEn'',          rec.STATUS_EN,          p_write_null => TRUE);
                APEX_JSON.write(''isDisabledAction'',  rec.IS_DISABLED_ACTION, p_write_null => TRUE);

                IF rec.CTO_ID IS NOT NULL THEN
                    APEX_JSON.open_object(''cto'');
                        APEX_JSON.write(''id'',    rec.CTO_ID,    p_write_null => TRUE);
                        APEX_JSON.write(''hours'', rec.CTO_HOURS, p_write_null => TRUE);
                    APEX_JSON.close_object;
                END IF;

                IF rec.OT_ID IS NOT NULL THEN
                    APEX_JSON.open_object(''overtime'');
                        APEX_JSON.write(''id'',       rec.OT_ID,          p_write_null => TRUE);
                        APEX_JSON.write(''fromTime'', rec.OT_FROM_TIME,   p_write_null => TR' || 'UE);
                        APEX_JSON.write(''toTime'',   rec.OT_TO_TIME,     p_write_null => TRUE);
                    APEX_JSON.close_object;
                END IF;

            APEX_JSON.close_object;
        END LOOP;

        APEX_JSON.close_array;
    APEX_JSON.close_object;

EXCEPTION
    WHEN OTHERS THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                        p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''حدث خطأ في النظام'',            p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''An unexpected error occurred'', p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''SYSTEM_ERROR'',                 p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 500;
END;
';

  ORDS.DEFINE_HANDLER(
      p_module_name    => 'MyEmployees',
      p_pattern        => 'Present',
      p_method         => 'GET',
      p_source_type    => 'plsql/block',
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => l_source);
  
  COMMIT;
END;
