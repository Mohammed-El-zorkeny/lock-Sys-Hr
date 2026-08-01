-- ====================================================================
-- ORDS REST Handler Update for POST /Users/CheckInAndOut
-- Date: 12-07-2026
-- Description:
--   Updates the Check-in/out handler to respect CHECK_LOCATION setting:
--   - If CHECK_LOCATION = 'Y': enforces geographic validation and blocks.
--   - If CHECK_LOCATION = 'N': bypasses geographic validation.
-- ====================================================================

DECLARE
  l_source CLOB;
BEGIN
  l_source := '
-- ============================================================
-- POST /api/v1/attendance/check
-- Module  : api/v1
-- Template: attendance/check
-- Method  : POST
-- Auth    : Token Required
-- Body    : siteId, checkType, attendanceDate, actualTime,
--           latitude, longitude, isFake, fakeLatitude, fakeLongitude, notes
-- ============================================================
DECLARE
    l_header_value    VARCHAR2(4000);
    l_bearer_token    VARCHAR2(4000);
    l_token           APEX_JWT.T_TOKEN;
    l_user_object     APEX_JSON.T_VALUES;
    l_user_id         NUMBER;
    l_user_type       VARCHAR2(200);
    l_iss             VARCHAR2(200);

    l_body            CLOB;
    l_body_values     APEX_JSON.T_VALUES;

    -- Body Variables
    l_site_id         NUMBER;
    l_employee_id     NUMBER;
    l_check_type      VARCHAR2(10);
    l_attendance_date DATE;
    l_actual_time     VARCHAR2(10);
    l_latitude        VARCHAR2(50);
    l_longitude   ' || '    VARCHAR2(50);
    l_is_fake         NUMBER := 0;
    l_fake_latitude   VARCHAR2(50);
    l_fake_longitude  VARCHAR2(50);
    l_notes           VARCHAR2(4000);
    l_username        VARCHAR2(200);

    -- Work Variables
    l_duplicate       NUMBER := 0;
    l_new_id          NUMBER;
    l_location_id     NUMBER;
    l_check_location  VARCHAR2(10);

BEGIN
    -- ===== 1. TOKEN VALIDATION =====
    l_header_value := OWA_UTIL.get_cgi_env(''Authorization'');

    IF l_header_value IS NULL OR INSTR(l_header_value, ''Bearer '') != 1 THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                  p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''???? ????? ?????? ?????'', p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''Authentication required'', p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''TOKEN_REQUIRED'',         p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 401;
        RETURN;
    END IF;

    l_bea' || 'rer_token := SUBSTR(l_header_value, 8);

    BEGIN
        l_token := APEX_JWT.DECODE(
            p_value         => l_bearer_token,
            p_signature_key => SYS.UTL_RAW.CAST_TO_RAW(''secretKey'')
        );
        APEX_JSON.PARSE(l_user_object, l_token.payload);

        IF NOT APEX_JSON.DOES_EXIST(p_path => ''sub'', p_values => l_user_object) THEN
            APEX_JSON.open_object;
            APEX_JSON.write(''status'',    ''error'',          p_write_null => TRUE);
            APEX_JSON.write(''messageAr'', ''Token ??? ????'', p_write_null => TRUE);
            APEX_JSON.write(''messageEn'', ''Invalid token'',  p_write_null => TRUE);
            APEX_JSON.write(''errorCode'', ''INVALID_TOKEN'',  p_write_null => TRUE);
            APEX_JSON.close_object;
            :status := 401;
            RETURN;
        END IF;

        l_iss := APEX_JSON.GET_VARCHAR2(p_path => ''iss'', p_values => l_user_object);

        IF l_iss IS NULL OR l_iss != ''ORDS'' THEN
            APEX_JSON.' || 'open_object;
            APEX_JSON.write(''status'',    ''error'',          p_write_null => TRUE);
            APEX_JSON.write(''messageAr'', ''Token ??? ????'', p_write_null => TRUE);
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
            APEX_JSON.write(''messageAr'', ''Token ??? ????'', p_write_null => TRUE);
            APEX_JSON.write(''messageEn'', ''Invalid token'',  p_write_null => TRUE);
            APE' || 'X_JSON.write(''errorCode'', ''INVALID_TOKEN'',  p_write_null => TRUE);
            APEX_JSON.close_object;
            :status := 401;
            RETURN;
    END;

    -- ===== 2. READ BODY =====
    l_body := :body_text;

    IF l_body IS NULL THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                      p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''?? ????? ?? ????? ????????'', p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''Request body is empty'',      p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''INVALID_REQUEST'',            p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 400;
        RETURN;
    END IF;

    APEX_JSON.PARSE(l_body_values, l_body);

    -- ===== 3. EXTRACT PARAMS =====
    l_site_id         := APEX_JSON.GET_NUMBER  (p_path => ''siteId'',          p_values => l_body_values);
    l_check_type      := UPPER(TRIM(APEX_JSON.GET_VARCHAR2(p_path ' || '=> ''checkType'',      p_values => l_body_values)));
    l_attendance_date := NVL(TO_DATE(TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''attendanceDate'', p_values => l_body_values)), ''DD/MM/YYYY''), TRUNC(SYSDATE));
    l_actual_time     := TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''actualTime'',     p_values => l_body_values));
    l_latitude        := TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''latitude'',       p_values => l_body_values));
    l_longitude       := TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''longitude'',      p_values => l_body_values));
    l_is_fake         := NVL(APEX_JSON.GET_NUMBER  (p_path => ''isFake'',         p_values => l_body_values), 0);
    l_fake_latitude   := TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''fakeLatitude'',   p_values => l_body_values));
    l_fake_longitude  := TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''fakeLongitude'',  p_values => l_body_values));
    l_notes           := TRIM(APEX_JSON.GET_VARCHAR2(p_path => ''notes'',          p_values => l_body_values));

    -- ??? ?' || '?? employee_id ? username ?? ??????
    BEGIN
        SELECT E.EMPLOYEE_ID, U.USERNAME, NVL(E.CHECK_LOCATION, ''Y'')
        INTO   l_employee_id, l_username, l_check_location
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
            APEX_JSON.write(''messageAr'', ''???????? ??? ????? ?????'',       p_write_null => TRUE);
            APEX_JSON.write(''messageEn'', ''User is not linked to employee'', p_write_null => TRUE);
            APEX_JSON.write(''errorCode'', ''EMPLOYEE_NOT_LINKED'',            p_write_null => TRUE);
            APEX_JSON.close_object;
            :status := 400;
            RETURN;
    END;

    -- ===== 4. VALIDATE REQUIRED =====
    IF l_check_type IS NULL THE' || 'N
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                  p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''??? ?????? ?????'',        p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''checkType is required'',  p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''MISSING_PARAM'',          p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 400;
        RETURN;
    END IF;

    IF l_check_type NOT IN (''IN'', ''OUT'') THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                        p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''??? ?????? ??? ?? ???? IN ?? OUT'', p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''checkType must be IN or OUT'', p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''INVALID_DATA'',                p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 400;
        RETURN;' || '
    END IF;

    IF l_site_id IS NULL THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',               p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''?????? ?????'',         p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''siteId is required'',  p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''MISSING_PARAM'',        p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 400;
        RETURN;
    END IF;

    IF l_latitude IS NULL OR l_longitude IS NULL THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                          p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''?????? ???????? ?????'',          p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''latitude and longitude are required'', p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''MISSING_PARAMS'',                 p_write_null => TRUE);
        APEX_JSON.cl' || 'ose_object;
        :status := 400;
        RETURN;
    END IF;

    -- ===== 5. CHECK DUPLICATE =====
    SELECT COUNT(*) INTO l_duplicate
    FROM   HR_ATTENDANCE_LOG
    WHERE  EMPLOYEE_ID              = l_employee_id
    AND    TRUNC(ATTENDANCE_DATE)   = TRUNC(l_attendance_date)
    AND    UPPER(CHECK_TYPE)        = l_check_type
    AND    STATUS                   = ''1'';

    IF l_duplicate > 0 THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                                                                          p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''?????? ???? ???? '' || CASE WHEN l_check_type = ''IN'' THEN ''????'' ELSE ''????'' END || '' ????? ?????? ???? ?????'', p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''Employee already has '' || l_check_type || '' record for this day'',               p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''DUPLICATE_ATTENDANCE'',                             ' || '                             p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 409;
        RETURN;
    END IF;

    -- ===== 6. CHECK OUT WITHOUT IN =====
    IF l_check_type = ''OUT'' THEN
        SELECT COUNT(*) INTO l_duplicate
        FROM   HR_ATTENDANCE_LOG
        WHERE  EMPLOYEE_ID            = l_employee_id
        AND    TRUNC(ATTENDANCE_DATE) = TRUNC(l_attendance_date)
        AND    UPPER(CHECK_TYPE)      = ''IN''
        AND    STATUS                 = ''1'';

        IF l_duplicate = 0 THEN
            APEX_JSON.open_object;
            APEX_JSON.write(''status'',    ''error'',                                        p_write_null => TRUE);
            APEX_JSON.write(''messageAr'', ''?? ???? ????? ???? ???? ????? ???? ???? ?????'', p_write_null => TRUE);
            APEX_JSON.write(''messageEn'', ''Cannot register OUT without IN record'',        p_write_null => TRUE);
            APEX_JSON.write(''errorCode'', ''MISSING_CHECK_IN'',                   ' || '          p_write_null => TRUE);
            APEX_JSON.close_object;
            :status := 400;
            RETURN;
        END IF;
    END IF;

    -- ===== 7. CALCULATE LOCATION_ID (GEO CHECK) =====
    -- ?? IS_FAKE = 1 ? LOCATION_ID ???? NULL ??? ??? (?????? ????)
    l_location_id := NULL;

    IF l_is_fake = 0 THEN
        BEGIN
            SELECT ID INTO l_location_id
            FROM   HR_SITE_LOCATIONS
            WHERE  SITE_ID = l_site_id
            AND    STATUS  = ''1''
            AND    ROWNUM  = 1
            AND    (
                      -- CIRCLE: ??????? ??? ???????? <= ???????? (??????)
                      (ZONE_TYPE IN (''CIRCLE'', ''BOTH'')
                       AND ZONE_RADIUS IS NOT NULL
                       AND (
                            6371000 * ACOS(
                                LEAST(1, GREATEST(-1,
                                    SIN(TO_NUMBER(LATITUDE)        * 3.141592653589793 / 180) * SIN(TO_NUMBER(l_latitude)  * 3.' || '141592653589793 / 180)
                                  + COS(TO_NUMBER(LATITUDE)        * 3.141592653589793 / 180) * COS(TO_NUMBER(l_latitude)  * 3.141592653589793 / 180)
                                  * COS((TO_NUMBER(l_longitude) - TO_NUMBER(LONGITUDE)) * 3.141592653589793 / 180)
                                ))
                            )
                           ) <= ZONE_RADIUS
                      )
                      OR
                      -- RECT: ?????????? ???? ????????
                      (ZONE_TYPE IN (''RECT'', ''BOTH'')
                       AND ZONE_LAT_NORTH IS NOT NULL AND ZONE_LAT_SOUTH IS NOT NULL
                       AND ZONE_LNG_EAST  IS NOT NULL AND ZONE_LNG_WEST  IS NOT NULL
                       AND TO_NUMBER(l_latitude)  BETWEEN TO_NUMBER(ZONE_LAT_SOUTH) AND TO_NUMBER(ZONE_LAT_NORTH)
                       AND TO_NUMBER(l_longitude) BETWEEN TO_NUMBER(ZONE_LNG_WEST)  AND TO_NUMBER(ZONE_LNG_EAST)
                      )
         ' || '          );
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_location_id := NULL;  -- ???? ?? ??????? ????????
            WHEN OTHERS THEN
                l_location_id := NULL;
        END;
    END IF;

    -- ===== 7.1 CHECK LOCATION LIMITATION (IF CHECK_LOCATION = Y) =====
    IF l_check_location = ''Y'' AND l_location_id IS NULL AND l_is_fake = 0 THEN
        APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''error'',                                                                         p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''عذراً، يجب تسجيل الحضور/الانصراف من داخل النطاق الجغرافي المحدد.'',                   p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''Sorry, you must check in/out within the designated geographic location.'',        p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''OUT_OF_RANGE'',                                                                   p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 400;
        RETURN;
    END IF;

    -- ===== 8. INSERT =====
    INSERT INTO HR_ATTENDANCE_LOG (
        EMPLOYEE_ID,
        SITES_ID,
        LOCATION_ID,
        CHECK_TYPE,
        CHECK_METHOD,
        ATTENDANCE_DATE,
        ACTUAL_TIME,
        LATITUDE,
        LONGITUDE,
        IS_FAKE,
        FAKE_LATITUDE,
        FAKE_LONGITUDE,
        MANUAL_USER_ID,
        STATUS,
        NOTES,
        CREATED_BY,
        CREATED_BY_USER_ID,
        CREATED_DATE
    ) VALUES (
        l_employee_id,
        l_site_id,
        l_location_id,
        l_check_type,
        ''MOBILE'',
        l_attendance_date,
        l_actual_time,
        l_latitude,
        l_longitude,
        l_is_fake,
        l_fake_latitude,
        l_fake_longitude,
        l_' || 'user_id,
        ''1'',
        l_notes,
        l_username,
        l_user_id,
        SYSDATE
    ) RETURNING ID INTO l_new_id;

    COMMIT;

    -- ===== 9. SUCCESS RESPONSE =====
    :status := 201;
    APEX_JSON.open_object;
        APEX_JSON.write(''status'',    ''success'',                                                                             p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''?? ????? '' || CASE WHEN l_check_type = ''IN'' THEN ''??????'' ELSE ''??????'' END || '' ?????'', p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', CASE WHEN l_check_type = ''IN'' THEN ''Check-in'' ELSE ''Check-out'' END || '' recorded successfully'', p_write_null => TRUE);
        APEX_JSON.open_object(''attendance'');
            APEX_JSON.write(''id'',             l_new_id,                                p_write_null => TRUE);
            APEX_JSON.write(''employeeId'',     l_employee_id,                           p_write_null => TRUE);
            APEX_JSON.write(''siteId' || ''',         l_site_id,                               p_write_null => TRUE);
            APEX_JSON.write(''locationId'',     l_location_id,                          p_write_null => TRUE);
            APEX_JSON.write(''checkType'',      l_check_type,                            p_write_null => TRUE);
            APEX_JSON.write(''checkMethod'',    ''MOBILE'',                                p_write_null => TRUE);
            APEX_JSON.write(''attendanceDate'', TO_CHAR(l_attendance_date, ''DD/MM/YYYY''), p_write_null => TRUE);
            APEX_JSON.write(''actualTime'',     l_actual_time,                           p_write_null => TRUE);
            APEX_JSON.write(''isFake'',         l_is_fake,                               p_write_null => TRUE);
            APEX_JSON.write(''isOutOfRange'',   CASE WHEN l_check_location = ''Y'' AND l_location_id IS NULL AND l_is_fake = 0 THEN TRUE ELSE FALSE END);
        APEX_JSON.close_object;
    APEX_JSON.close_object;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        APEX_JSON.' || 'open_object;
        APEX_JSON.write(''status'',    ''error'',                        p_write_null => TRUE);
        APEX_JSON.write(''messageAr'', ''??? ??? ?? ??????'',            p_write_null => TRUE);
        APEX_JSON.write(''messageEn'', ''An unexpected error occurred'', p_write_null => TRUE);
        APEX_JSON.write(''errorCode'', ''SYSTEM_ERROR'',                 p_write_null => TRUE);
        APEX_JSON.close_object;
        :status := 500;
END;';

  ORDS.DEFINE_HANDLER(
      p_module_name    => 'Users',
      p_pattern        => 'CheckInAndOut',
      p_method         => 'POST',
      p_source_type    => 'plsql/block',
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => l_source);

  COMMIT;
END;
