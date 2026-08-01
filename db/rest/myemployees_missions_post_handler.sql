-- ====================================================================
-- ORDS REST Handler Update for POST /MyEmployees/Missions
-- Date: 12-07-2026
-- Description:
--   Updates the POST handler to accept and insert MISSION_TYPE_ID directly.
--   Removes the legacy MISSION_TYPE column completely.
-- ====================================================================

DECLARE
  l_source CLOB;
BEGIN
  l_source := '
DECLARE
    l_header_value      VARCHAR2(4000);
    l_bearer_token      VARCHAR2(4000);
    l_token             APEX_JWT.T_TOKEN;
    l_user_object       APEX_JSON.T_VALUES;
    l_user_id           NUMBER;
    l_user_type         VARCHAR2(200);
    l_iss               VARCHAR2(200);

    l_body              CLOB;
    l_body_values       APEX_JSON.T_VALUES;

    l_username          VARCHAR2(200);
    l_company_id        NUMBER;
    l_branch_id         NUMBER;

    -- Body Variables
    l_employee_id       NUMBER;
    l_start_date        DATE;
    l_end_date          DATE;
    l_mission_type_id   NUMBER;
    l_destination       VARCHAR2(200);
    l_mission_purpose   VARCHAR2(500);
    l_notes             VARCHAR2(1000);

    -- Work Variables
    l_new_id            NUMBER;
    l_emp_check         NUMBER := 0;

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
        :status := 401;
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

        IF l_iss IS NULL OR l_iss != ''ORDS'' THEN
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
            APEX_JSON.write(''messageEn'', ''Invalid token'',  p_write_null => TRUE);
            APEX_JSON.write(''errorCode'', ''INVALID_TOKEN'',  p_write_null => TRUE);
            APEX_JSON.close_object;
            :status := 401;
            RETURN;
    END;

    -- ===== 2. GET USER INFO =====
    BEGIN
        SELECT U.USERNAME, U.DEFAULT_COMPANY_ID, U.DEFAULT_BRANCH_ID
        INTO   l_username, l_company_id, l_branch_id
        FROM   SEC_USERS U
        WHERE  U.ID = l_user_id
        AND    ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            APEX_JSON.open_object;
            APEX_JSON.write(''status'',    ''error'',               p_write_null => TRUE);
            APEX_JSON.write(''messageAr'', ''المستخدم غير موجود'',   p_write_null => TRUE);
            APEX_JSON.write(''messageEn'', ''User not found'',      p_write_null => TRUE);
            APEX_JSON.write(''errorCode'', ''USER_NOT_FOUND'',       p_write_null => TRUE);
            APEX_JSON.close_object;
            :status := 404;
            RETURN;
    END;

    -- ===== 3. READ BODY =====
    l_body := :body_text;

    IF l_body IS NULL THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                      p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''لم نتمكن من قراءة البيانات'', p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''Request body is empty'',      p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''INVALID_REQUEST'',            p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 400;
        RETURN;
    END IF;

    APEX_JSON.PARSE(l_body_values, l_body);

    -- ===== 4. EXTRACT PARAMS =====
    l_employee_id     := APEX_JSON.GET_NUMBER(p_path => ''employeeId'', p_values => l_body_values);
    l_start_date      := TO_DATE(TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''startDate'',      p_values => l_body_values)), ''DD/MM/YYYY'');
    l_end_date        := TO_DATE(TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''endDate'',        p_values => l_body_values)), ''DD/MM/YYYY'');
    l_mission_type_id := APEX_JSON.GET_NUMBER(p_path => ''missionTypeId'', p_values => l_body_values);
    l_destination     := TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''destination'',     p_values => l_body_values));
    l_mission_purpose := TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''missionPurpose'',  p_values => l_body_values));
    l_notes           := TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''notes'',           p_values => l_body_values));

    -- ===== 5. VALIDATE REQUIRED =====
    IF l_employee_id IS NULL THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                  p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''رقم الموظف مطلوب'',        p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''employeeId is required'', p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''MISSING_PARAM'',           p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 400;
        RETURN;
    END IF;

    IF l_start_date IS NULL THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                 p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''تاريخ البداية مطلوب'',   p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''startDate is required'', p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''MISSING_PARAM'',          p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 400;
        RETURN;
    END IF;

    IF l_end_date IS NULL THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',               p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''تاريخ النهاية مطلوب'',  p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''endDate is required'', p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''MISSING_PARAM'',        p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 400;
        RETURN;
    END IF;

    IF l_end_date < l_start_date THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                                    p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''تاريخ النهاية يجب أن يكون بعد تاريخ البداية'', p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''endDate must be after startDate'',          p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''INVALID_DATE_RANGE'',                       p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 400;
        RETURN;
    END IF;

    -- ===== 5.1 MISSION TYPE VALIDATION =====
    IF l_mission_type_id IS NULL THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                             p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''نوع المهمة مطلوب'',                  p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''missionTypeId is required'',         p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''MISSING_PARAM'',                      p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 400;
        RETURN;
    END IF;

    BEGIN
        SELECT ID
        INTO   l_mission_type_id
        FROM   HR_MISSION_TYPES
        WHERE  ID = l_mission_type_id
        AND    STATUS = ''1''
        AND    IS_MOBILE_APP = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            APEX_JSON.open_object;
            APEX_JSON.write(''status'',    ''error'',                           p_write_null => TRUE);
            APEX_JSON.write(''messageAr'', ''نوع المهمة غير صالح أو غير متاح للموبايل'', p_write_null => TRUE);
            APEX_JSON.write(''messageEn'', ''Invalid or inactive mission type'', p_write_null => TRUE);
            APEX_JSON.write(''errorCode'', ''INVALID_MISSION_TYPE'',            p_write_null => TRUE);
            APEX_JSON.close_object;
            :status := 400;
            RETURN;
    END;

    -- ===== 6. CHECK EMPLOYEE EXISTS =====
    SELECT COUNT(*) INTO l_emp_check
    FROM   HR_EMPLOYEES
    WHERE  EMPLOYEE_ID = l_employee_id;

    IF l_emp_check = 0 THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',               p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''الموظف غير موجود'',    p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''Employee not found'',  p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''EMPLOYEE_NOT_FOUND'',  p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 404;
        RETURN;
    END IF;

    -- ===== 7. INSERT =====
    INSERT INTO HR_EMPLOYEE_MISSIONS (
        COMPANY_ID,
        BRANCH_ID,
        EMPLOYEE_ID,
        MISSION_TYPE_ID,
        REQUEST_DATE,
        START_DATE,
        END_DATE,
        DESTINATION,
        MISSION_PURPOSE,
        NOTES,
        STATUS_ID,
        CREATED_BY,
        CREATED_BY_USER_ID,
        CREATED_DATE
    ) VALUES (
        l_company_id,
        l_branch_id,
        l_employee_id,
        l_mission_type_id,
        SYSDATE,
        l_start_date,
        l_end_date,
        l_destination,
        l_mission_purpose,
        l_notes,
        4,
        l_username,
        l_user_id,
        SYSDATE
    ) RETURNING ID INTO l_new_id;

    COMMIT;

    -- ===== 8. SUCCESS RESPONSE =====
    :status := 201;
    APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''success'',                   p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''تم إضافة المهمة بنجاح'',     p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''Mission added successfully'', p_write_null => TRUE);
        APEX_JSON.open_object(''mission'');
            APEX_JSON.write(''id'',             l_new_id,                              p_write_null => TRUE);
            APEX_JSON.write(''employeeId'',     l_employee_id,                         p_write_null => TRUE);
            APEX_JSON.write(''missionTypeId'',  l_mission_type_id,                     p_write_null => TRUE);
            APEX_JSON.write(''startDate'',      TO_CHAR(l_start_date, ''DD/MM/YYYY''),   p_write_null => TRUE);
            APEX_JSON.write(''endDate'',        TO_CHAR(l_end_date,   ''DD/MM/YYYY''),   p_write_null => TRUE);
            APEX_JSON.write(''destination'',    l_destination,                         p_write_null => TRUE);
            APEX_JSON.write(''missionPurpose'', l_mission_purpose,                     p_write_null => TRUE);
            APEX_JSON.write(''notes'',          l_notes,                               p_write_null => TRUE);
            APEX_JSON.write(''statusId'',       4,                                     p_write_null => TRUE);
            APEX_JSON.write(''requestDate'',    TO_CHAR(SYSDATE, ''DD/MM/YYYY''),        p_write_null => TRUE);
        APEX_JSON.close_object;
    APEX_JSON.close_object;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                        p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''حدث خطأ في النظام'',            p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''An unexpected error occurred'', p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''SYSTEM_ERROR'',                 p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 500;
END;';

  ORDS.DEFINE_HANDLER(
      p_module_name    => 'MyEmployees',
      p_pattern        => 'Missions',
      p_method         => 'POST',
      p_source_type    => 'plsql/block',
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => l_source);

  COMMIT;
END;
