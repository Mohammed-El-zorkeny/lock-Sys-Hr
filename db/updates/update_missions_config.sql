-- ====================================================================
-- Database Schema Updates for Mission Types Integration
-- Date: 12-07-2026
-- Description:
--   Adds MISSION_TYPE_ID column to HR_EMPLOYEE_MISSIONS table safely
--   and establishes foreign key reference to HR_MISSION_TYPES.
-- ====================================================================

DECLARE
    l_col_exists NUMBER;
BEGIN
    -- Check if MISSION_TYPE_ID already exists in HR_EMPLOYEE_MISSIONS
    SELECT COUNT(*) INTO l_col_exists
    FROM   USER_TAB_COLUMNS
    WHERE  TABLE_NAME = 'HR_EMPLOYEE_MISSIONS'
    AND    COLUMN_NAME = 'MISSION_TYPE_ID';

    IF l_col_exists = 0 THEN
        -- Add MISSION_TYPE_ID column
        EXECUTE IMMEDIATE 'ALTER TABLE HR_EMPLOYEE_MISSIONS ADD (MISSION_TYPE_ID NUMBER)';
        
        -- Add Foreign Key Constraint
        EXECUTE IMMEDIATE 'ALTER TABLE HR_EMPLOYEE_MISSIONS ADD CONSTRAINT FK_HR_EMP_MSS_TYPE 
                           FOREIGN KEY (MISSION_TYPE_ID) REFERENCES HR_MISSION_TYPES(ID)';
        
        DBMS_OUTPUT.PUT_LINE('Column MISSION_TYPE_ID added successfully.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Column MISSION_TYPE_ID already exists.');
    END IF;
END;
/
