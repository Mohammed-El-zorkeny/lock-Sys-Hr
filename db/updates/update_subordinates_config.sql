-- ====================================================================
-- Database Schema Updates for Manager Subordinate Exceptions
-- Date: 12-07-2026
-- Description:
--   1) Adds SUBORDINATE_SOURCE column to HR_EMPLOYEES table.
--   2) Creates HR_MANAGER_DEPT_EXCEPTIONS table to map managers to
--      specific whitelisted departments.
-- ====================================================================

-- 1) Add SUBORDINATE_SOURCE to HR_EMPLOYEES
-- Valid values: 'STRUCTURE' (default) or 'EXCEPTIONS'
ALTER TABLE HR_EMPLOYEES ADD (
    SUBORDINATE_SOURCE VARCHAR2(20) DEFAULT 'STRUCTURE' NOT NULL
);

-- Add constraint to enforce valid values (optional, but recommended for integrity)
ALTER TABLE HR_EMPLOYEES ADD CONSTRAINT CHK_HR_EMP_SUB_SOURCE CHECK (
    SUBORDINATE_SOURCE IN ('    ', 'EXCEPTIONS')
);

-- Initialize all existing employees explicitly to 'STRUCTURE'
UPDATE HR_EMPLOYEES SET SUBORDINATE_SOURCE = 'STRUCTURE';
COMMIT;


-- 2) Create HR_MANAGER_DEPT_EXCEPTIONS Table
CREATE TABLE HR_MANAGER_DEPT_EXCEPTIONS (
    EMPLOYEE_ID   NUMBER NOT NULL,              -- Manager Employee ID
    DEPARTMENT_ID NUMBER NOT NULL,              -- Whitelisted Department ID
    STATUS        NUMBER(1) DEFAULT 1 NOT NULL, -- Status (1 for Active, 0 for Inactive)
    NOTES         VARCHAR2(500),                -- Optional remarks
    CONSTRAINT PK_HR_MANAGER_DEPT_EXC PRIMARY KEY (EMPLOYEE_ID, DEPARTMENT_ID),
    CONSTRAINT FK_MGR_DEPT_EMP FOREIGN KEY (EMPLOYEE_ID) REFERENCES HR_EMPLOYEES(EMPLOYEE_ID),
    CONSTRAINT FK_MGR_DEPT_DEPT FOREIGN KEY (DEPARTMENT_ID) REFERENCES HR_DEPARTMENT(ID),
    CONSTRAINT CHK_HR_MGR_DEPT_EXC_STATUS CHECK (STATUS IN (0, 1))
);

-- Index for performance when querying a manager's exceptions
CREATE INDEX IDX_HR_MGR_DEPT_EXC_MGR ON HR_MANAGER_DEPT_EXCEPTIONS(EMPLOYEE_ID, STATUS);
