-- ====================================================================
-- ORDS REST Registration for GET /MyEmployees/MissionType
-- Date: 12-07-2026
-- Description:
--   Creates a template and handler to fetch active mission types that
--   are enabled for the mobile app (IS_MOBILE_APP = 1).
-- ====================================================================

DECLARE
  l_source CLOB;
BEGIN
  -- Define the template
  ORDS.DEFINE_TEMPLATE(
      p_module_name    => 'MyEmployees',
      p_pattern        => 'MissionType',
      p_priority       => 0,
      p_etag_type      => 'HASH',
      p_etag_query     => NULL,
      p_comments       => NULL);

  -- Define the source code for the handler
  l_source := '
DECLARE
    l_header_value    VARCHAR2(4000);
    l_bearer_token    VARCHAR2(4000);
    l_token           APEX_JWT.T_TOKEN;
    l_user_object     APEX_JSON.T_VALUES;
    l_user_id         NUMBER;
    l_iss             VARCHAR2(200);
    l_total           NUMBER := 0;

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

        l_user_id := TO_NUMBER(APEX_JSON.GET_VARCHAR2(p_path => ''sub'', p_values => l_user_object));

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

    -- ===== 2. GET TOTAL =====
    SELECT COUNT(*) INTO l_total
    FROM   HR_MISSION_TYPES
    WHERE  STATUS = ''1''
    AND    IS_MOBILE_APP = 1;

    -- ===== 3. SUCCESS RESPONSE =====
    :status := 200;
    APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''success'',                          p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''تم جلب أنواع المهمات بنجاح'',        p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''Mission types retrieved successfully'', p_write_null => TRUE);
        APEX_JSON.write(''total'',     l_total,                              p_write_null => TRUE);

        APEX_JSON.open_array(''missionTypes'');

        FOR rec IN (
            SELECT ID, CODE, NAME, ARABIC_NAME, MAX_DAYS_PER_MONTH, MAX_DAYS_PER_YEAR, 
                   IS_PAID, REQUIRES_ATTACHMENT, NOTES, MISSION_TYPES
            FROM   HR_MISSION_TYPES
            WHERE  STATUS = ''1''
            AND    IS_MOBILE_APP = 1
            ORDER BY ID
        ) LOOP
            APEX_JSON.open_object;
                APEX_JSON.write(''id'',                 rec.ID,                  p_write_null => TRUE);
                APEX_JSON.write(''code'',               rec.CODE,                p_write_null => TRUE);
                APEX_JSON.write(''nameEn'',             rec.NAME,                p_write_null => TRUE);
                APEX_JSON.write(''nameAr'',             rec.ARABIC_NAME,         p_write_null => TRUE);
                APEX_JSON.write(''maxDaysPerMonth'',    rec.MAX_DAYS_PER_MONTH,  p_write_null => TRUE);
                APEX_JSON.write(''maxDaysPerYear'',     rec.MAX_DAYS_PER_YEAR,   p_write_null => TRUE);
                APEX_JSON.write(''isPaid'',             rec.IS_PAID,             p_write_null => TRUE);
                APEX_JSON.write(''requiresAttachment'', rec.REQUIRES_ATTACHMENT, p_write_null => TRUE);
                APEX_JSON.write(''notes'',              rec.NOTES,               p_write_null => TRUE);
                APEX_JSON.write(''classification'',     rec.MISSION_TYPES,       p_write_null => TRUE);
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
END;';

  -- Define the handler
  ORDS.DEFINE_HANDLER(
      p_module_name    => 'MyEmployees',
      p_pattern        => 'MissionType',
      p_method         => 'GET',
      p_source_type    => 'plsql/block',
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => l_source);

  COMMIT;
END;
