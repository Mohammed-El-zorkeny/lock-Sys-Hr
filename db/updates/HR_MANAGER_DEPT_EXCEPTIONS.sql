-- ====================================================================
-- Table: HR_MANAGER_DEPT_EXCEPTIONS
-- Date: 12-07-2026
-- Description:
--   Creates the table, sequence, and trigger for manager department
--   exceptions, conforming to the oracle-apex-tables skill guidelines.
-- ====================================================================

-- 1) Create Table
CREATE TABLE HR_MANAGER_DEPT_EXCEPTIONS (
    ID                  NUMBER NOT NULL,
    COMPANY_ID          NUMBER NOT NULL,
    BRANCH_ID           NUMBER NOT NULL,
    CODE                VARCHAR2(50),
    EMPLOYEE_ID         NUMBER NOT NULL,
    DEPARTMENT_ID       NUMBER NOT NULL,
    STATUS              VARCHAR2(10) DEFAULT '1',
    NOTES               VARCHAR2(4000),
    CREATED_BY_USER_ID  NUMBER,
    CREATED_BY          VARCHAR2(1000),
    CREATED_DATE        DATE,
    UPDATED_BY_USER_ID  NUMBER,
    UPDATED_BY          VARCHAR2(1000),
    UPDATED_DATE        DATE,
    CONSTRAINT HR_MANAGER_DEPT_EXCEPTIONS_PK PRIMARY KEY (ID),
    CONSTRAINT HR_MANAGER_DEPT_EXCEPTIONS_UQ UNIQUE (EMPLOYEE_ID, DEPARTMENT_ID),
    CONSTRAINT HR_MANAGER_DEPT_EXC_FK_EMP FOREIGN KEY (EMPLOYEE_ID) REFERENCES HR_EMPLOYEES(EMPLOYEE_ID),
    CONSTRAINT HR_MANAGER_DEPT_EXC_FK_DEPT FOREIGN KEY (DEPARTMENT_ID) REFERENCES HR_DEPARTMENT(ID),
    CONSTRAINT CHK_HR_MGR_DEPT_EXC_STATUS CHECK (STATUS IN ('0', '1'))
);

-- Index for fast lookup on manager exceptions
CREATE INDEX IDX_HR_MGR_DEPT_EXC_MGR ON HR_MANAGER_DEPT_EXCEPTIONS(EMPLOYEE_ID, STATUS);

-- 2) Create Sequence
CREATE SEQUENCE HR_MANAGER_DEPT_EXCEPTIONS_SEQ
    START WITH 1
    INCREMENT BY 1
    NOCACHE;

-- 3) Create Trigger
CREATE OR REPLACE TRIGGER TRG_HR_MANAGER_DEPT_EXCEPTIONS_AUD
    BEFORE INSERT OR UPDATE
    ON HR_MANAGER_DEPT_EXCEPTIONS
    FOR EACH ROW
DECLARE
    V_MAX_CODE NUMBER;
BEGIN
    IF INSERTING THEN
        -- 1) ID from Sequence
        IF :NEW.ID IS NULL THEN
            SELECT HR_MANAGER_DEPT_EXCEPTIONS_SEQ.NEXTVAL INTO :NEW.ID FROM DUAL;
        END IF;

        -- 2) Audit - Insert
        :NEW.CREATED_DATE       := SYSDATE;
        :NEW.CREATED_BY         := NVL(V('APP_USER'), USER);
        :NEW.CREATED_BY_USER_ID := V('P0_USER_ID');

        -- 3) Status default
        IF :NEW.STATUS IS NULL THEN
            :NEW.STATUS := '1';
        END IF;

        -- 4) Company
        IF :NEW.COMPANY_ID IS NULL THEN
            :NEW.COMPANY_ID := V('P_COMPANY_ID');
        END IF;

        -- 5) Branch
        IF :NEW.BRANCH_ID IS NULL THEN
            :NEW.BRANCH_ID := V('P_BRANCH_ID');
        END IF;

        -- 6) Auto CODE generation
        IF :NEW.CODE IS NULL THEN
            SELECT NVL(MAX(TO_NUMBER(REGEXP_SUBSTR(CODE, '\d+$'))), 0) + 1
            INTO   V_MAX_CODE
            FROM   HR_MANAGER_DEPT_EXCEPTIONS
            WHERE  CODE LIKE 'EXC-%'
            AND    COMPANY_ID = :NEW.COMPANY_ID;

            :NEW.CODE := 'EXC-' || LPAD(V_MAX_CODE, 6, '0');
        END IF;
    END IF;

    IF UPDATING THEN
        -- Audit - Update
        :NEW.UPDATED_DATE       := SYSDATE;
        :NEW.UPDATED_BY         := NVL(V('APP_USER'), USER);
        :NEW.UPDATED_BY_USER_ID := V('P0_USER_ID');
    END IF;
END;
/
ALTER TRIGGER TRG_HR_MANAGER_DEPT_EXCEPTIONS_AUD ENABLE;
