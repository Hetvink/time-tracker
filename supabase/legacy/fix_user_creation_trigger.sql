-- ============================================================================
-- Fix User Creation Trigger for OAuth Authentication
-- ============================================================================
-- Run this script in your Supabase SQL Editor to ensure users are automatically
-- created when they sign up via Google OAuth
-- ============================================================================

-- Step 1: Check if the trigger exists
SELECT
    tgname as trigger_name,
    tgrelid::regclass as table_name,
    tgtype,
    tgenabled
FROM pg_trigger
WHERE tgname = 'on_auth_user_created';

-- If the above query returns no rows, the trigger doesn't exist!

-- ============================================================================
-- Step 2: Create or replace the function that handles new user creation
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert new user into public.users table
    -- Use INSERT with ON CONFLICT to handle race conditions
    INSERT INTO public.users (id, email, role, created_at)
    VALUES (
        NEW.id,
        NEW.email,
        'member'::user_role,
        NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        updated_at = NOW();

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Log the error but don't fail the auth signup
        RAISE WARNING 'Error creating user profile: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Step 3: Create the trigger on auth.users table
-- ============================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- Step 4: Verify the trigger was created
-- ============================================================================

SELECT
    tgname as trigger_name,
    tgrelid::regclass as table_name,
    tgtype,
    CASE tgenabled
        WHEN 'O' THEN 'Enabled'
        WHEN 'D' THEN 'Disabled'
        ELSE 'Unknown'
    END as status
FROM pg_trigger
WHERE tgname = 'on_auth_user_created';

-- Expected output:
-- trigger_name          | table_name  | tgtype | status
-- on_auth_user_created | auth.users  | 5      | Enabled

-- ============================================================================
-- Step 5: Test the trigger (optional)
-- ============================================================================

-- You can test by checking if users exist after OAuth signup:
-- SELECT * FROM public.users ORDER BY created_at DESC LIMIT 10;

-- ============================================================================
-- Troubleshooting
-- ============================================================================

-- If you see errors about the user_role enum not existing, run:
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('admin', 'member');
    END IF;
END$$;

-- If you see errors about the users table not existing, run the main schema:
-- See: supabase_schema.sql

-- ============================================================================
-- Notes
-- ============================================================================
-- 1. This trigger runs automatically when a new user signs up via OAuth
-- 2. The ON CONFLICT clause prevents duplicate key errors
-- 3. The SECURITY DEFINER allows the function to insert into public.users
--    even though the auth.users table is in a different schema
-- 4. The EXCEPTION handler ensures auth signup succeeds even if user
--    profile creation fails (app will create it as fallback)
