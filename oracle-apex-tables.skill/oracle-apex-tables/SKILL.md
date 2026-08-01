---
name: oracle-apex-tables
description: |
  Use this skill whenever creating Oracle database tables, triggers, sequences, indexes, LOVs, or translations for an Oracle APEX application.
  Triggers include: user asks to create a table, add columns, create a trigger, make a sequence, build indexes, write LOV queries, or add APEX translations.
  Also use when the user mentions: جدول, trigger, sequence, index, LOV, ترجمة, Oracle, APEX, or any table creation/modification task.
  This skill defines ALL naming conventions, audit patterns, code generation rules, and translation standards.
  ALWAYS read this skill before creating any database object.
---

# Oracle APEX Tables & Database Objects Skill

## Environment
- **Database:** Oracle
- **Frontend:** Oracle APEX (App ID: 1000)
- **Test Data:** COMPANY_ID = 2, BRANCH_ID = 10

---

## Naming Conventions

### Table Names
- Medical tables: `MED_` prefix (MED_PATIENTS, MED_DOCTORS, MED_SERVICES)
- Purchase tables: `PUR_` prefix
- Sales tables: `SAL_` prefix
- HR tables: `HR_` prefix
- General/shared tables: `GNL_` prefix
- Security tables: `SEC_` prefix
- Stock/Inventory tables: `STOCK_` prefix

### Column Names
- Arabic name column: **ARABIC_NAME** (NOT NAME_AR, NOT NAME_ARABIC)
- English name column: **NAME**
- Primary key: **ID** (NUMBER NOT NULL)
- Company: **COMPANY_ID** (NUMBER NOT NULL)
- Branch: **BRANCH_ID** (NUMBER NOT NULL)
- Auto code: **CODE** (VARCHAR2(50))
- Status: **STATUS** (VARCHAR2(10) DEFAULT '1')
- Notes: **NOTES** (VARCHAR2(4000))

### Audit Columns (MANDATORY on every table)
```sql
CREATED_BY_USER_ID  NUMBER,
CREATED_BY          VARCHAR2(1000),
CREATED_DATE        DATE,
UPDATED_BY_USER_ID  NUMBER,
UPDATED_BY          VARCHAR2(1000),
UPDATED_DATE        DATE
```

### Sequence Naming
- Pattern: `{TABLE_NAME}_SEQ`
- Example: `MED_PATIENTS_SEQ`, `GNL_STATUS_SEQ`
- Always: `START WITH 1 INCREMENT BY 1 NOCACHE`

### Trigger Naming
- Pattern: `TRG_{TABLE_NAME}_AUD`
- Example: `TRG_MED_PATIENTS_AUD`, `TRG_GNL_STATUS_AUD`

### Index Naming
- Pattern: `IDX_{SHORT_TABLE_NAME}_{COLUMN_NAME}`
- Example: `IDX_PATIENTS_COMPANY`, `IDX_STATUS_TABLE`

### Constraint Naming
- Primary Key: `{TABLE_NAME}_PK`
- Foreign Key: `{TABLE_NAME}_FK_{REFERENCE}`
- Unique: `{TABLE_NAME}_UQ`
- Check: `CHK_{TABLE_NAME}_{COLUMN}`

---

## Trigger Pattern (MANDATORY)

Every trigger MUST follow this exact pattern (same as TRG_HR_ADMIN_DECISIONS_AUD):

```sql
CREATE OR REPLACE TRIGGER TRG_{TABLE_NAME}_AUD
    BEFORE INSERT OR UPDATE
    ON {TABLE_NAME}
    FOR EACH ROW
DECLARE
    V_MAX_CODE NUMBER;
BEGIN
    IF INSERTING THEN
        -- 1) ID from Sequence
        IF :NEW.ID IS NULL THEN
            SELECT {TABLE_NAME}_SEQ.NEXTVAL INTO :NEW.ID FROM DUAL;
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

        -- 6) Auto CODE (if applicable)
        IF :NEW.CODE IS NULL THEN
            SELECT NVL(MAX(TO_NUMBER(REGEXP_SUBSTR(CODE, '\d+$'))), 0) + 1
            INTO   V_MAX_CODE
            FROM   {TABLE_NAME}
            WHERE  CODE LIKE '{PREFIX}-%'
            AND    COMPANY_ID = :NEW.COMPANY_ID;

            :NEW.CODE := '{PREFIX}-' || LPAD(V_MAX_CODE, 6, '0');
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
ALTER TRIGGER TRG_{TABLE_NAME}_AUD ENABLE;
```

### Trigger Order (STRICT):
1. ID from Sequence
2. Audit (CREATED_DATE, CREATED_BY, CREATED_BY_USER_ID)
3. STATUS default
4. COMPANY_ID
5. BRANCH_ID
6. Auto CODE generation
7. Any custom logic

---

## LOV Conventions

### Dynamic LOV Display Format
```sql
CODE || ' - ' || DECODE(V('P_LANG'), 'ar', NVL(ARABIC_NAME, NAME), NAME)
```
- Return Value: **ID** (NUMBER)
- Always filter by: `COMPANY_ID`, `BRANCH_ID`, `STATUS = '1'`

### Static LOV Display Format
```sql
DECODE(V('P_LANG'), 'ar',
    DECODE(CODE, 'VAL1','عربي1', 'VAL2','عربي2'),
    INITCAP(CODE)
) AS DISPLAY_VALUE,
CODE AS RETURN_VALUE
```
- Return Value: **CODE** (UPPERCASE in database)
- Display: `INITCAP(CODE)` for English, Arabic DECODE for Arabic

### Hierarchical LOV (Template)
```javascript
function(options) {
  var lang = apex.locale.getLanguage();
  var paddingDir = (lang === 'ar') ? 'padding-right' : 'padding-left';
  options.display = 'list';
  options.recordTemplate = ('<li data-id="~RETURN_VALUE." data-disabled="~IS_DISABLED." style="' + paddingDir + ':~LEVEL.em;line-height:1.8;padding-top:6px;padding-bottom:6px;font-weight:~FONT_WEIGHT.;">~DISPLAY_VALUE.</li>').replace(/~/g, "&");
  return options;
}
```
- Parent RETURN_VALUE: Use **negative ID** (`ID * -1`) — NOT text like 'CAT_1'
- Parent: `IS_DISABLED = 'true'`, `FONT_WEIGHT = 'bold'`
- Child: `IS_DISABLED = 'false'`, `FONT_WEIGHT = 'normal'`

---

## Translation Conventions (APEX_LANG)

### Pattern
```sql
BEGIN
    APEX_LANG.CREATE_MESSAGE(
        p_application_id    => 1000,
        p_name              => '{MESSAGE_KEY}',
        p_language          => 'en',
        p_message_text      => '{English Text}',
        p_used_in_javascript => TRUE
    );
    APEX_LANG.CREATE_MESSAGE(
        p_application_id    => 1000,
        p_name              => '{MESSAGE_KEY}',
        p_language          => 'ar',
        p_message_text      => '{Arabic Text}',
        p_used_in_javascript => TRUE
    );
END;
/
```

### Rules
- `p_used_in_javascript` => **TRUE** always
- `p_application_id` => **1000** always
- Each message in its own `BEGIN/END` block (to identify duplicates)
- Plural labels: DOCTORS/الأطباء, ROOMS/الغرف
- Singular labels with ال: DOCTOR/الطبيب, ROOM/الغرفة

---

## Test Data Conventions

- COMPANY_ID = **2**
- BRANCH_ID = **10**
- Saudi nationals: Document Type = `'National ID'`, ID starts with `10`
- Residents: Document Type = `'Iqama'`, ID starts with `23`
- Foreigners: Document Type = `'Passport'`
- Gender: `'M'` / `'F'`
- Status: `'1'` (active) / `'0'` (inactive)
- Realistic Arabic/English names
- Balanced gender distribution (50/50)

---

## File Output
- All SQL files go to `/mnt/user-data/outputs/`
- File naming: `{TABLE_NAME}.sql` or `{TABLE_NAME}_{PURPOSE}.sql`
- Always use `present_files` to share with user

---

## Existing Key Tables Reference
- **GNL_STATUS** — Generic statuses (TABLE_NAME, NEXT_STATUS_IDS, IS_INITIAL, IS_FINAL, ALLOW_EDIT, COLOR_ID)
- **GNL_APPROVAL_TEMPLATES** — Approval workflow templates
- **GNL_APPROVAL_STEPS** — Approval steps (SEQUENTIAL/ANY)
- **GNL_APPROVAL_TASKS** — Runtime approval tasks
- **COLORS** — Color reference table (BG_COLOR, TEXT_COLOR, BADGE_CSS_CLASS)
- **SEC_PAGES** — Application pages
- **SEC_MODULE** — Application modules
- **SEC_TRANSACTION_RIGHTS** — Data access rights (ALL/DEPT/OWN)
- **SEC_PAGES_MANDATORY** — Mandatory pages per company/branch
- **MED_PATIENTS** — Patients (CODE=PAT-, MRN=MRN-)
- **MED_DOCTORS** — Doctors
- **MED_SERVICES** — Services (SERVICE_TYPE: SERVICE/PACKAGE)
- **MED_SERVICE_CATEGORIES** — Service categories (hierarchical)
- **MED_PRICE_LISTS / MED_PRICE_LIST_DTL** — Price lists
- **MED_INSURANCE_COMPANIES / CONTRACTS / CLASSES** — Insurance
- **MED_BUILDINGS / FLOORS / DEPARTMENTS / ROOMS / BEDS** — Infrastructure
- **DBS_STOCK_ITEMS** — Stock items (ITEM_TYPE: GOODS/SERVICE/COMBO)
- **GNL_BANK** — Banks
- **PUR_REQUISITION** — Purchase requisitions
