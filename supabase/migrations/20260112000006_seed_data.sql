-- Migration: Seed data from local MySQL database
-- This migrates tenants, users, subscriptions, and jobs

-- ============================================================
-- STEP 1: Insert Tenants
-- ============================================================
-- Note: Converting 'tnt-superadmin-0001' to a proper UUID

INSERT INTO public.tenants (id, name, domain, slug, plan, status, created_by, failed_reason, created_at, updated_at, deleted_at)
VALUES
  -- Superadmin tenant (converted ID)
  ('00000000-0000-0000-0000-000000000001', 'Recrutr Platform', 'admin.recrutr.in', 'admin', 'STARTER', 'ACTIVE', NULL, NULL, '2025-09-26 23:42:44+00', '2025-09-26 23:42:44+00', NULL),
  -- Demo tenant
  ('23795788-10be-4459-8a90-e5d90b693e20', 'Demo', 'test-demo', 'demo', 'STARTER', 'ACTIVE', '00000000-0000-0000-0000-000000000001', NULL, '2025-10-02 12:48:12+00', '2025-10-03 09:03:15+00', NULL),
  -- Demo2 tenant
  ('b3bf1707-fbbf-4407-abb8-f5332ce12473', 'Demo2', 'test-demo-2', 'demo2', 'ENTERPRISE', 'ACTIVE', '00000000-0000-0000-0000-000000000001', NULL, '2025-10-12 11:00:24+00', '2025-10-12 11:00:24+00', NULL)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- STEP 2: Insert Users into auth.users
-- ============================================================
-- Note: Converting 'u-superadmin-0001' to proper UUID
-- Passwords are bcrypt hashed, compatible with Supabase

INSERT INTO auth.users (
  id,
  instance_id,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  aud,
  role,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
)
VALUES
  -- Superadmin user (converted ID)
  (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'superadmin@recrutr.in',
    '$2a$10$tV/w8CWIX3Zfw1eqV8Y6TeVrpJWYGj5R122jm/vohNEfnIRlaSZvS',
    '2025-09-26 23:47:57+00',
    '{"provider": "email", "providers": ["email"]}',
    '{"full_name": "Recrutr Super Admin", "tenant_id": "00000000-0000-0000-0000-000000000001", "role": "SUPERADMIN"}',
    'authenticated',
    'authenticated',
    '2025-09-26 23:47:57+00',
    '2025-09-26 23:47:57+00',
    '',
    '',
    '',
    ''
  ),
  -- Demo tenant admin
  (
    '08428c58-6103-44f9-9e6c-183bf13e4e60',
    '00000000-0000-0000-0000-000000000000',
    'ameykode@demo.com',
    '$2a$10$kxl1.2TQsxyEXlsNbF72ce6KPDvbLX52okOhTS3spcfcB/HrOlpTy',
    '2025-10-02 12:48:12+00',
    '{"provider": "email", "providers": ["email"]}',
    '{"full_name": "Amey Kode", "tenant_id": "23795788-10be-4459-8a90-e5d90b693e20", "role": "ADMIN"}',
    'authenticated',
    'authenticated',
    '2025-10-02 12:48:12+00',
    '2025-10-20 15:44:54+00',
    '',
    '',
    '',
    ''
  ),
  -- Demo2 tenant admin
  (
    '895d2d2a-632f-4052-a7f8-619f1b82c8a7',
    '00000000-0000-0000-0000-000000000000',
    'ameykode@demo2.com',
    '$2a$10$cgxy8VOFMsp4h.s5i1FYpOyrlr1YLPKg1yEgTPz00SUQAoPKFX48m',
    '2025-10-12 11:00:24+00',
    '{"provider": "email", "providers": ["email"]}',
    '{"full_name": "Amey Kode", "tenant_id": "b3bf1707-fbbf-4407-abb8-f5332ce12473", "role": "ADMIN"}',
    'authenticated',
    'authenticated',
    '2025-10-12 11:00:24+00',
    '2025-10-20 15:34:05+00',
    '',
    '',
    '',
    ''
  )
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- STEP 3: Insert User Profiles
-- ============================================================
-- These link to auth.users and contain tenant/role info

INSERT INTO public.user_profiles (id, tenant_id, name, role, is_owner, is_active, force_password_reset, created_at, updated_at, deleted_at)
VALUES
  -- Superadmin
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Recrutr Super Admin', 'SUPERADMIN', TRUE, TRUE, FALSE, '2025-09-26 23:47:57+00', '2025-09-26 23:47:57+00', NULL),
  -- Demo admin
  ('08428c58-6103-44f9-9e6c-183bf13e4e60', '23795788-10be-4459-8a90-e5d90b693e20', 'Amey Kode', 'ADMIN', TRUE, TRUE, FALSE, '2025-10-02 12:48:12+00', '2025-10-20 15:44:54+00', NULL),
  -- Demo2 admin
  ('895d2d2a-632f-4052-a7f8-619f1b82c8a7', 'b3bf1707-fbbf-4407-abb8-f5332ce12473', 'Amey Kode', 'ADMIN', TRUE, TRUE, FALSE, '2025-10-12 11:00:24+00', '2025-10-20 15:34:05+00', NULL)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- STEP 4: Insert Subscriptions
-- ============================================================

INSERT INTO public.subscriptions (tenant_id, plan, billing_cycle, status, currency, amount_cents, period_start, period_end, trial_ends_at, next_renewal_at, canceled_at, updated_by, created_at, updated_at)
VALUES
  ('23795788-10be-4459-8a90-e5d90b693e20', 'STARTER', 'MONTHLY', 'ACTIVE', 'USD', 0, '2025-10-02 12:48:12+00', '2025-11-02 12:48:12+00', NULL, '2025-11-02 12:48:12+00', NULL, '00000000-0000-0000-0000-000000000001', '2025-10-02 12:48:12+00', '2025-10-02 12:48:12+00'),
  ('b3bf1707-fbbf-4407-abb8-f5332ce12473', 'ENTERPRISE', 'MONTHLY', 'ACTIVE', 'USD', 0, '2025-10-12 05:30:25+00', '2025-11-12 05:30:25+00', NULL, '2025-11-12 05:30:25+00', NULL, '00000000-0000-0000-0000-000000000001', '2025-10-12 05:30:25+00', '2025-10-12 05:30:25+00')
ON CONFLICT (tenant_id) DO NOTHING;

-- ============================================================
-- STEP 5: Insert Jobs
-- ============================================================

INSERT INTO public.jobs (id, tenant_id, title, description, location, department, created_at, updated_at, extra, is_public, publish_at, expire_at, external_apply_url)
VALUES
  ('cc688e25-c193-43e4-b50c-abe713e6a8dd', '23795788-10be-4459-8a90-e5d90b693e20', 'SSE', '<p>We are looking for an experienced backend engineer to join our team.</p>', 'Pune', 'Engineering', '2025-10-20 06:54:34.175611+00', '2025-10-20 07:54:35+00', '{}', TRUE, '2025-10-20 07:28:00+00', '2025-10-28 07:28:00+00', NULL),
  ('fc180081-e251-416f-a978-9d1686eb7a36', '23795788-10be-4459-8a90-e5d90b693e20', 'Intern', '<p>Intern for Sales</p>', 'Pune', 'Sales', '2025-10-20 08:00:29.021834+00', '2025-10-20 15:26:58+00', '{}', TRUE, '2025-10-20 08:00:00+00', '2025-10-28 08:00:00+00', NULL),
  ('fde8793a-b9c3-4639-9fcf-c0f29de98723', 'b3bf1707-fbbf-4407-abb8-f5332ce12473', 'Software Engineer', '<p>Looking for software engineer who can code in python and react</p>', 'Gurgaon', 'Operations', '2025-10-21 03:39:18.184025+00', '2025-10-21 03:39:18.184025+00', '{"salary_range": "₹14,00,000"}', TRUE, NULL, NULL, NULL)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- STEP 6: Insert auth.identities (required for Supabase Auth)
-- ============================================================

INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '{"sub": "00000000-0000-0000-0000-000000000001", "email": "superadmin@recrutr.in"}', 'email', '00000000-0000-0000-0000-000000000001', '2025-09-26 23:47:57+00', '2025-09-26 23:47:57+00', '2025-09-26 23:47:57+00'),
  ('08428c58-6103-44f9-9e6c-183bf13e4e60', '08428c58-6103-44f9-9e6c-183bf13e4e60', '{"sub": "08428c58-6103-44f9-9e6c-183bf13e4e60", "email": "ameykode@demo.com"}', 'email', '08428c58-6103-44f9-9e6c-183bf13e4e60', '2025-10-02 12:48:12+00', '2025-10-02 12:48:12+00', '2025-10-20 15:44:54+00'),
  ('895d2d2a-632f-4052-a7f8-619f1b82c8a7', '895d2d2a-632f-4052-a7f8-619f1b82c8a7', '{"sub": "895d2d2a-632f-4052-a7f8-619f1b82c8a7", "email": "ameykode@demo2.com"}', 'email', '895d2d2a-632f-4052-a7f8-619f1b82c8a7', '2025-10-12 11:00:24+00', '2025-10-12 11:00:24+00', '2025-10-20 15:34:05+00')
ON CONFLICT (id) DO NOTHING;
