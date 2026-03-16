-- Все оставшиеся журналы: новые типы + колонки в haccp_quality_logs (и генеральные уборки через quality)

-- Новые значения enum
DO $$ BEGIN
  ALTER TYPE haccp_log_type ADD VALUE 'med_examinations';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TYPE haccp_log_type ADD VALUE 'disinfectant_accounting';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TYPE haccp_log_type ADD VALUE 'equipment_washing';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TYPE haccp_log_type ADD VALUE 'sieve_filter_magnet';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Медосмотры (предварительные/периодические)
ALTER TABLE public.haccp_quality_logs
  ADD COLUMN IF NOT EXISTS med_exam_employee_name TEXT,
  ADD COLUMN IF NOT EXISTS med_exam_dob TEXT,
  ADD COLUMN IF NOT EXISTS med_exam_gender TEXT,
  ADD COLUMN IF NOT EXISTS med_exam_position TEXT,
  ADD COLUMN IF NOT EXISTS med_exam_department TEXT,
  ADD COLUMN IF NOT EXISTS med_exam_hire_date DATE,
  ADD COLUMN IF NOT EXISTS med_exam_type TEXT,
  ADD COLUMN IF NOT EXISTS med_exam_institution TEXT,
  ADD COLUMN IF NOT EXISTS med_exam_harmful_1 TEXT,
  ADD COLUMN IF NOT EXISTS med_exam_harmful_2 TEXT,
  ADD COLUMN IF NOT EXISTS med_exam_date DATE,
  ADD COLUMN IF NOT EXISTS med_exam_conclusion TEXT,
  ADD COLUMN IF NOT EXISTS med_exam_employer_decision TEXT,
  ADD COLUMN IF NOT EXISTS med_exam_next_date DATE,
  ADD COLUMN IF NOT EXISTS med_exam_exclusion_date DATE;

-- Учёт дезсредств (расчёт потребности + поступление)
ALTER TABLE public.haccp_quality_logs
  ADD COLUMN IF NOT EXISTS disinf_object_name TEXT,
  ADD COLUMN IF NOT EXISTS disinf_object_count NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS disinf_area_sqm NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS disinf_treatment_type TEXT,
  ADD COLUMN IF NOT EXISTS disinf_frequency_per_month INT,
  ADD COLUMN IF NOT EXISTS disinf_agent_name TEXT,
  ADD COLUMN IF NOT EXISTS disinf_concentration_pct TEXT,
  ADD COLUMN IF NOT EXISTS disinf_consumption_per_sqm NUMERIC(10, 4),
  ADD COLUMN IF NOT EXISTS disinf_solution_per_treatment NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS disinf_need_per_treatment NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS disinf_need_per_month NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS disinf_need_per_year NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS disinf_receipt_date DATE,
  ADD COLUMN IF NOT EXISTS disinf_invoice_number TEXT,
  ADD COLUMN IF NOT EXISTS disinf_quantity NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS disinf_expiry_date DATE,
  ADD COLUMN IF NOT EXISTS disinf_responsible_name TEXT;

-- Мойка и дезинфекция оборудования
ALTER TABLE public.haccp_quality_logs
  ADD COLUMN IF NOT EXISTS wash_time TEXT,
  ADD COLUMN IF NOT EXISTS wash_equipment_name TEXT,
  ADD COLUMN IF NOT EXISTS wash_solution_name TEXT,
  ADD COLUMN IF NOT EXISTS wash_solution_concentration_pct TEXT,
  ADD COLUMN IF NOT EXISTS wash_disinfectant_name TEXT,
  ADD COLUMN IF NOT EXISTS wash_disinfectant_concentration_pct TEXT,
  ADD COLUMN IF NOT EXISTS wash_rinsing_temp TEXT,
  ADD COLUMN IF NOT EXISTS wash_controller_signature TEXT;

-- Генеральные уборки (график)
ALTER TABLE public.haccp_quality_logs
  ADD COLUMN IF NOT EXISTS gen_clean_premises TEXT,
  ADD COLUMN IF NOT EXISTS gen_clean_date DATE,
  ADD COLUMN IF NOT EXISTS gen_clean_responsible TEXT;

-- Сита/фильтры/магнитоуловители
ALTER TABLE public.haccp_quality_logs
  ADD COLUMN IF NOT EXISTS sieve_no TEXT,
  ADD COLUMN IF NOT EXISTS sieve_name_location TEXT,
  ADD COLUMN IF NOT EXISTS sieve_condition TEXT,
  ADD COLUMN IF NOT EXISTS sieve_cleaning_date DATE,
  ADD COLUMN IF NOT EXISTS sieve_signature TEXT,
  ADD COLUMN IF NOT EXISTS sieve_comments TEXT;
