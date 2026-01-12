-- RTR API Role-Based RLS Policies
-- Based on rtr-user-auth-service RBAC system
-- Roles: SUPERADMIN (cross-tenant), ADMIN, HR, INTERVIEWER, CANDIDATE

------------------------------------------------------------
-- DROP EXISTING NON-ROLE-BASED POLICIES
------------------------------------------------------------

-- Tenants
DROP POLICY IF EXISTS "Users can view own tenant" ON tenants;
DROP POLICY IF EXISTS "Service role full access to tenants" ON tenants;

-- Jobs
DROP POLICY IF EXISTS "Users can view own tenant jobs" ON jobs;
DROP POLICY IF EXISTS "Users can insert own tenant jobs" ON jobs;
DROP POLICY IF EXISTS "Users can update own tenant jobs" ON jobs;
DROP POLICY IF EXISTS "Users can delete own tenant jobs" ON jobs;
DROP POLICY IF EXISTS "Anyone can view public jobs" ON jobs;

-- Applications
DROP POLICY IF EXISTS "Users can view own tenant applications" ON applications;
DROP POLICY IF EXISTS "Users can insert own tenant applications" ON applications;
DROP POLICY IF EXISTS "Users can update own tenant applications" ON applications;
DROP POLICY IF EXISTS "Users can delete own tenant applications" ON applications;

-- User Profiles
DROP POLICY IF EXISTS "Users can view own tenant profiles" ON user_profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON user_profiles;

-- Pipelines
DROP POLICY IF EXISTS "Users can view own tenant pipelines" ON pipelines;
DROP POLICY IF EXISTS "Users can insert own tenant pipelines" ON pipelines;
DROP POLICY IF EXISTS "Users can update own tenant pipelines" ON pipelines;
DROP POLICY IF EXISTS "Users can delete own tenant pipelines" ON pipelines;

-- Pipeline Assignments
DROP POLICY IF EXISTS "Users can view own tenant pipeline assignments" ON pipeline_assignments;
DROP POLICY IF EXISTS "Users can insert own tenant pipeline assignments" ON pipeline_assignments;
DROP POLICY IF EXISTS "Users can update own tenant pipeline assignments" ON pipeline_assignments;
DROP POLICY IF EXISTS "Users can delete own tenant pipeline assignments" ON pipeline_assignments;

-- Candidate Stage Progress
DROP POLICY IF EXISTS "Users can view own tenant candidate progress" ON candidate_stage_progress;
DROP POLICY IF EXISTS "Users can insert own tenant candidate progress" ON candidate_stage_progress;
DROP POLICY IF EXISTS "Users can update own tenant candidate progress" ON candidate_stage_progress;

-- Stage Feedback
DROP POLICY IF EXISTS "Users can view own tenant stage feedback" ON stage_feedback;
DROP POLICY IF EXISTS "Users can insert own tenant stage feedback" ON stage_feedback;
DROP POLICY IF EXISTS "Users can update own tenant stage feedback" ON stage_feedback;

-- Tenant Settings
DROP POLICY IF EXISTS "Users can view own tenant settings" ON tenant_settings;
DROP POLICY IF EXISTS "Users can update own tenant settings" ON tenant_settings;
DROP POLICY IF EXISTS "Users can insert own tenant settings" ON tenant_settings;

-- Subscriptions
DROP POLICY IF EXISTS "Users can view own tenant subscription" ON subscriptions;
DROP POLICY IF EXISTS "Service role manages subscriptions" ON subscriptions;

-- Audit Logs
DROP POLICY IF EXISTS "Users can view own tenant audit logs" ON audit_logs;
DROP POLICY IF EXISTS "Service role inserts audit logs" ON audit_logs;

------------------------------------------------------------
-- HELPER FUNCTIONS
------------------------------------------------------------

-- Get user's role from user_profiles
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT AS $$
  SELECT COALESCE(
    (SELECT role FROM public.user_profiles WHERE id = auth.uid()),
    'CANDIDATE'
  );
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- Check if user is SUPERADMIN
CREATE OR REPLACE FUNCTION public.is_superadmin()
RETURNS BOOLEAN AS $$
  SELECT public.get_user_role() = 'SUPERADMIN';
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- Check if user has job management permission (ADMIN, HR)
CREATE OR REPLACE FUNCTION public.can_manage_jobs()
RETURNS BOOLEAN AS $$
  SELECT public.get_user_role() IN ('SUPERADMIN', 'ADMIN', 'HR');
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- Check if user has application management permission
CREATE OR REPLACE FUNCTION public.can_manage_applications()
RETURNS BOOLEAN AS $$
  SELECT public.get_user_role() IN ('SUPERADMIN', 'ADMIN', 'HR');
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- Check if user has feedback permission (ADMIN, HR, INTERVIEWER)
CREATE OR REPLACE FUNCTION public.can_manage_feedback()
RETURNS BOOLEAN AS $$
  SELECT public.get_user_role() IN ('SUPERADMIN', 'ADMIN', 'HR', 'INTERVIEWER');
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- Check if user has settings permission (ADMIN only)
CREATE OR REPLACE FUNCTION public.can_manage_settings()
RETURNS BOOLEAN AS $$
  SELECT public.get_user_role() IN ('SUPERADMIN', 'ADMIN');
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- Check if user has member management permission (ADMIN only)
CREATE OR REPLACE FUNCTION public.can_manage_members()
RETURNS BOOLEAN AS $$
  SELECT public.get_user_role() IN ('SUPERADMIN', 'ADMIN');
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

------------------------------------------------------------
-- TENANTS POLICIES
------------------------------------------------------------
-- SUPERADMIN: full cross-tenant access
CREATE POLICY "Superadmin full access to tenants" ON tenants
  FOR ALL USING (public.is_superadmin());

-- Others: view own tenant only
CREATE POLICY "Users can view own tenant" ON tenants
  FOR SELECT USING (
    NOT public.is_superadmin()
    AND id = public.get_tenant_id()
  );

------------------------------------------------------------
-- JOBS POLICIES
------------------------------------------------------------
-- SUPERADMIN: full access to all jobs
CREATE POLICY "Superadmin full access to jobs" ON jobs
  FOR ALL USING (public.is_superadmin());

-- ADMIN/HR: full access to own tenant jobs
CREATE POLICY "Managers can manage tenant jobs" ON jobs
  FOR ALL USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.can_manage_jobs()
  );

-- INTERVIEWER: read-only access to own tenant jobs
CREATE POLICY "Interviewers can view tenant jobs" ON jobs
  FOR SELECT USING (
    tenant_id = public.get_tenant_id()
    AND public.get_user_role() = 'INTERVIEWER'
  );

-- CANDIDATE/Public: read public jobs only
CREATE POLICY "Anyone can view public jobs" ON jobs
  FOR SELECT USING (
    is_public = TRUE
    AND publish_at <= NOW()
    AND (expire_at IS NULL OR expire_at > NOW())
  );

------------------------------------------------------------
-- APPLICATIONS POLICIES
------------------------------------------------------------
-- SUPERADMIN: full access
CREATE POLICY "Superadmin full access to applications" ON applications
  FOR ALL USING (public.is_superadmin());

-- ADMIN/HR: full access to own tenant
CREATE POLICY "Managers can manage applications" ON applications
  FOR ALL USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.can_manage_applications()
  );

-- INTERVIEWER: read-only
CREATE POLICY "Interviewers can view applications" ON applications
  FOR SELECT USING (
    tenant_id = public.get_tenant_id()
    AND public.get_user_role() = 'INTERVIEWER'
  );

-- CANDIDATE: view own applications only
CREATE POLICY "Candidates can view own applications" ON applications
  FOR SELECT USING (
    public.get_user_role() = 'CANDIDATE'
    AND applicant_email = (SELECT email FROM auth.users WHERE id = auth.uid())
  );

-- CANDIDATE: create applications
CREATE POLICY "Candidates can create applications" ON applications
  FOR INSERT WITH CHECK (
    public.get_user_role() = 'CANDIDATE'
    AND applicant_email = (SELECT email FROM auth.users WHERE id = auth.uid())
  );

------------------------------------------------------------
-- USER PROFILES POLICIES
------------------------------------------------------------
-- SUPERADMIN: full access
CREATE POLICY "Superadmin full access to profiles" ON user_profiles
  FOR ALL USING (public.is_superadmin());

-- ADMIN: manage tenant users
CREATE POLICY "Admin can manage tenant users" ON user_profiles
  FOR ALL USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.can_manage_members()
  );

-- Others: view own tenant profiles
CREATE POLICY "Users can view tenant profiles" ON user_profiles
  FOR SELECT USING (
    NOT public.is_superadmin()
    AND NOT public.can_manage_members()
    AND tenant_id = public.get_tenant_id()
  );

-- Everyone: update own profile
CREATE POLICY "Users can update own profile" ON user_profiles
  FOR UPDATE USING (id = auth.uid());

------------------------------------------------------------
-- PIPELINES POLICIES
------------------------------------------------------------
-- SUPERADMIN: full access
CREATE POLICY "Superadmin full access to pipelines" ON pipelines
  FOR ALL USING (public.is_superadmin());

-- ADMIN/HR: full access
CREATE POLICY "Managers can manage pipelines" ON pipelines
  FOR ALL USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.can_manage_jobs()
  );

-- INTERVIEWER: read-only
CREATE POLICY "Interviewers can view pipelines" ON pipelines
  FOR SELECT USING (
    tenant_id = public.get_tenant_id()
    AND public.get_user_role() = 'INTERVIEWER'
  );

------------------------------------------------------------
-- PIPELINE ASSIGNMENTS POLICIES
------------------------------------------------------------
-- SUPERADMIN: full access
CREATE POLICY "Superadmin full access to pipeline assignments" ON pipeline_assignments
  FOR ALL USING (public.is_superadmin());

-- ADMIN/HR: full access
CREATE POLICY "Managers can manage pipeline assignments" ON pipeline_assignments
  FOR ALL USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.can_manage_jobs()
  );

-- INTERVIEWER: read-only
CREATE POLICY "Interviewers can view pipeline assignments" ON pipeline_assignments
  FOR SELECT USING (
    tenant_id = public.get_tenant_id()
    AND public.get_user_role() = 'INTERVIEWER'
  );

------------------------------------------------------------
-- CANDIDATE STAGE PROGRESS POLICIES
------------------------------------------------------------
-- SUPERADMIN: full access
CREATE POLICY "Superadmin full access to candidate progress" ON candidate_stage_progress
  FOR ALL USING (public.is_superadmin());

-- ADMIN/HR/INTERVIEWER: full access (they manage interviews)
CREATE POLICY "Team can manage candidate progress" ON candidate_stage_progress
  FOR ALL USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.can_manage_feedback()
  );

------------------------------------------------------------
-- STAGE FEEDBACK POLICIES
------------------------------------------------------------
-- SUPERADMIN: full access
CREATE POLICY "Superadmin full access to feedback" ON stage_feedback
  FOR ALL USING (public.is_superadmin());

-- ADMIN/HR/INTERVIEWER: full access (they give feedback)
CREATE POLICY "Team can manage feedback" ON stage_feedback
  FOR ALL USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.can_manage_feedback()
  );

------------------------------------------------------------
-- TENANT SETTINGS POLICIES
------------------------------------------------------------
-- SUPERADMIN: full access
CREATE POLICY "Superadmin full access to settings" ON tenant_settings
  FOR ALL USING (public.is_superadmin());

-- ADMIN: manage own tenant settings
CREATE POLICY "Admin can manage tenant settings" ON tenant_settings
  FOR ALL USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.can_manage_settings()
  );

-- Others: read-only (for branding, features)
CREATE POLICY "Users can view tenant settings" ON tenant_settings
  FOR SELECT USING (
    NOT public.is_superadmin()
    AND NOT public.can_manage_settings()
    AND tenant_id = public.get_tenant_id()
  );

------------------------------------------------------------
-- SUBSCRIPTIONS POLICIES
------------------------------------------------------------
-- SUPERADMIN: full access (billing system)
CREATE POLICY "Superadmin full access to subscriptions" ON subscriptions
  FOR ALL USING (public.is_superadmin());

-- ADMIN: read-only (view billing status)
CREATE POLICY "Admin can view subscription" ON subscriptions
  FOR SELECT USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.get_user_role() = 'ADMIN'
  );

------------------------------------------------------------
-- AUDIT LOGS POLICIES
------------------------------------------------------------
-- SUPERADMIN: full access
CREATE POLICY "Superadmin full access to audit logs" ON audit_logs
  FOR ALL USING (public.is_superadmin());

-- ADMIN: view own tenant audit logs
CREATE POLICY "Admin can view tenant audit logs" ON audit_logs
  FOR SELECT USING (
    NOT public.is_superadmin()
    AND public.get_user_role() = 'ADMIN'
    AND (target_tenant_id = public.get_tenant_id() OR actor_tenant_id = public.get_tenant_id())
  );

-- Service role: insert audit logs (for backend logging)
CREATE POLICY "Service role inserts audit logs" ON audit_logs
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
