-- Fix RLS policies on applications table that query auth.users
-- Replace subquery with auth.jwt() ->> 'email' which doesn't require table access
-- The old policies queried auth.users directly, causing "permission denied for table users"

-- Drop the problematic policies
DROP POLICY IF EXISTS "Candidates can create applications" ON applications;
DROP POLICY IF EXISTS "Candidates can view own applications" ON applications;

-- Recreate with auth.jwt() instead of auth.users subquery
CREATE POLICY "Candidates can create applications" ON applications
  FOR INSERT
  WITH CHECK (
    get_user_role() = 'CANDIDATE'
    AND applicant_email = (auth.jwt() ->> 'email')
  );

CREATE POLICY "Candidates can view own applications" ON applications
  FOR SELECT
  USING (
    get_user_role() = 'CANDIDATE'
    AND applicant_email = (auth.jwt() ->> 'email')
  );
