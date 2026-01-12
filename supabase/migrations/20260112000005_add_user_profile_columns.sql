-- Migration: Add missing columns to user_profiles
-- The original users table had more fields that we need to add

-- Add force_password_reset column
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS force_password_reset BOOLEAN NOT NULL DEFAULT FALSE;

-- Add phone column (from original users table)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS phone VARCHAR(50);

-- Add avatar_url column (useful for profile pictures)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(500);

-- Add last_login_at column (for tracking)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

-- Add email_verified column (backup for Supabase auth state)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;

-- Create index on force_password_reset for queries
CREATE INDEX IF NOT EXISTS idx_user_profiles_force_reset
ON user_profiles(tenant_id, force_password_reset)
WHERE force_password_reset = TRUE;

-- Update the handle_new_user trigger to include new columns
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.user_profiles (
    id,
    tenant_id,
    name,
    role,
    force_password_reset,
    email_verified
  )
  VALUES (
    NEW.id,
    COALESCE(
      (NEW.raw_user_meta_data->>'tenant_id')::UUID,
      '00000000-0000-0000-0000-000000000000'::UUID
    ),
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'role', 'CANDIDATE'),
    COALESCE((NEW.raw_user_meta_data->>'force_password_reset')::BOOLEAN, FALSE),
    COALESCE(NEW.email_confirmed_at IS NOT NULL, FALSE)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
