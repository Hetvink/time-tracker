-- ============================================================================
-- GENERATE FAKE DATA SCRIPT (Refined & Strict)
-- ============================================================================
-- Usage:
-- 1. Replace 'REPLACE_WITH_USER_EMAIL' with the actual user's email.
-- 2. Run this script in the Supabase SQL Editor.
-- ============================================================================

DO $$
DECLARE
    -- CONFIGURATION
    target_email TEXT := 'REPLACE_WITH_USER_EMAIL'; -- <--- CHANGE THIS
    curr_month_start DATE := '2026-01-01';
    
    -- VARIABLES
    target_user_id UUID;
    v_session_id UUID;
    v_prev_session_id UUID := NULL; -- Track previous session for linking
    v_check_in TIMESTAMP WITH TIME ZONE;
    v_check_out TIMESTAMP WITH TIME ZONE;
    v_date DATE;
    v_activity_time TIMESTAMP WITH TIME ZONE;
    i INTEGER;
    rand_idx INTEGER;
    
    -- APP LIST
    apps TEXT[] := ARRAY['VS Code', 'Google Chrome', 'Slack', 'Terminal', 'Simulator'];
    titles TEXT[] := ARRAY['editing generate_data.sql', 'Stack Overflow - SQL loops', '#general - Huddle', 'npm run dev', 'iPhone 15 Pro'];
BEGIN
    -- 1. Get User ID
    SELECT id INTO target_user_id FROM public.users WHERE email = target_email;
    
    IF target_user_id IS NULL THEN
        RAISE EXCEPTION 'User with email % not found.', target_email;
    END IF;

    RAISE NOTICE 'Generating data for User: % (ID: %)', target_email, target_user_id;

    -- ========================================================================
    -- SCENARIO 1: Normal Work Days (Jan 1-9)
    -- ========================================================================
    FOR i IN 1..9 LOOP
        v_date := curr_month_start + (i - 1) * INTERVAL '1 day';
        
        -- Skip weekends
        IF EXTRACT(DOW FROM v_date) IN (0, 6) THEN 
            CONTINUE; 
        END IF;

        v_check_in := v_date + TIME '09:00:00'; 
        v_check_out := v_date + TIME '17:00:00'; 
        
        INSERT INTO public.attendance_sessions (
            user_id, check_in_time, check_out_time, check_in_time_utc, check_out_time_utc,
            total_work_seconds, is_closed, check_in_source, check_out_source, created_at
        ) VALUES (
            target_user_id, v_check_in, v_check_out, 
            v_check_in AT TIME ZONE 'UTC', v_check_out AT TIME ZONE 'UTC',
            EXTRACT(EPOCH FROM (v_check_out - v_check_in))::INTEGER,
            true, 'script_generated', 'manual_checkout', NOW()
        ) RETURNING id INTO v_session_id;

        -- Generate App Activities (every 30 mins)
        v_activity_time := v_check_in;
        WHILE v_activity_time < v_check_out LOOP
            rand_idx := floor(random() * 5 + 1)::int;
            
            INSERT INTO public.app_activities (
                session_id, user_id, app_name, window_title,
                start_time, end_time, start_time_utc, end_time_utc,
                duration_seconds
            ) VALUES (
                v_session_id, target_user_id, apps[rand_idx], titles[rand_idx],
                v_activity_time, v_activity_time + INTERVAL '25 minutes',
                v_activity_time AT TIME ZONE 'UTC', (v_activity_time + INTERVAL '25 minutes') AT TIME ZONE 'UTC',
                1500 -- 25 mins
            );
            v_activity_time := v_activity_time + INTERVAL '30 minutes';
        END LOOP;
    END LOOP;

    -- ========================================================================
    -- SCENARIO 2: 3-Day Non-Stop Sleep (Jan 10-13) - SPLIT SESSIONS & STRICT BOUNDS
    -- ========================================================================
    
    DECLARE
        v_start_date DATE := curr_month_start + INTERVAL '9 days';  -- Jan 10
        v_end_date DATE := curr_month_start + INTERVAL '12 days';   -- Jan 13
        v_curr_date DATE;
        
        v_sess_start TIMESTAMP;
        v_sess_end TIMESTAMP;
        v_sleep_start TIMESTAMP;
        v_sleep_end TIMESTAMP;
        
        -- Transition variables
        v_check_in_src TEXT;
        v_check_out_src TEXT;
        v_cont_of_id INTEGER; -- Using INTEGER might fail if ID is UUID. Wait.
                              -- The app uses INTEGER IDs locally, but UUIDs for Supabase.
                              -- If `attendance_sessions.id` is UUID (implied by `v_session_id UUID`), 
                              -- then `continuation_of_session_id` should effectively link, but linking UUIDs requires column type match.
                              -- Assuming standard Supabase setup here. CHECK: The prompt implies `v_session_id UUID`.
                              -- If `continuation_of_session_id` is INT (from local DB schema), we can't easily link UUIDs here.
                              -- Let's check schema assumption. The local DB uses INTEGER. The Supabase schema usually uses UUID or BigInt.
                              -- `generate_fake_data.sql` implies Supabase execution.
                              -- I will SKIP explicit ID linking (continuation_of_session_id) to avoid type errors unless I'm sure.
                              -- But I *can* set `continuation_reason`.
    BEGIN
        v_curr_date := v_start_date;
        
        WHILE v_curr_date <= v_end_date LOOP
            -- A. Determine Session Bounds & Sources
            v_check_in_src := 'manual_checkin';
            v_check_out_src := 'manual_checkout';
            
            IF v_curr_date = v_start_date THEN
                v_sess_start := v_curr_date + TIME '10:00:00'; -- Start of entire marathon
                v_check_in_src := 'manual_checkin';
            ELSE
                v_sess_start := v_curr_date + TIME '00:00:00'; -- Midnight start
                v_check_in_src := 'auto_midnight_transition'; -- Auto Check-in at midnight
            END IF;
            
            IF v_curr_date = v_end_date THEN
                v_sess_end := v_curr_date + TIME '08:00:00'; -- End of entire marathon
                v_check_out_src := 'manual_checkout';
            ELSE
                v_sess_end := v_curr_date + TIME '23:59:59'; -- End of day
                v_check_out_src := 'auto_midnight_transition'; -- Auto Check-out at 11:59:59 PM
            END IF;
            
            -- B. Determine Sleep Bounds (Strictly inside session)
            IF v_curr_date = v_start_date THEN
                v_sleep_start := v_curr_date + TIME '14:00:00';
            ELSE
                v_sleep_start := v_curr_date + TIME '00:00:00';
            END IF;
            
            IF v_curr_date = v_end_date THEN
                v_sleep_end := v_curr_date + TIME '06:00:00';
            ELSE
                v_sleep_end := v_curr_date + TIME '23:59:59';
            END IF;

            -- Safety Check
            IF v_sleep_start < v_sess_start THEN v_sleep_start := v_sess_start; END IF;
            IF v_sleep_end > v_sess_end THEN v_sleep_end := v_sess_end; END IF;

            -- Create Session with Explicit Transition Sources
            INSERT INTO public.attendance_sessions (
                user_id, check_in_time, check_out_time, check_in_time_utc, check_out_time_utc,
                total_work_seconds, is_closed, check_in_source, check_out_source, continuation_reason, created_at
            ) VALUES (
                target_user_id, v_sess_start, v_sess_end, 
                v_sess_start AT TIME ZONE 'UTC', v_sess_end AT TIME ZONE 'UTC',
                EXTRACT(EPOCH FROM (v_sess_end - v_sess_start))::INTEGER,
                true, 
                v_check_in_src, 
                v_check_out_src,
                CASE WHEN v_curr_date > v_start_date THEN 'midnight_transition' ELSE NULL END, -- Explicit reason
                NOW()
            ) RETURNING id INTO v_session_id;

            -- Create Work During Sleep
            IF v_sleep_start < v_sleep_end THEN
                INSERT INTO public.work_during_sleep_periods (
                    session_id, user_id, sleep_start_time, wake_time, 
                    sleep_start_time_utc, wake_time_utc, duration_seconds, note
                ) VALUES (
                    v_session_id, target_user_id, 
                    v_sleep_start, v_sleep_end,
                    v_sleep_start AT TIME ZONE 'UTC', v_sleep_end AT TIME ZONE 'UTC',
                    EXTRACT(EPOCH FROM (v_sleep_end - v_sleep_start))::INTEGER,
                    'Massive 3-day sleep (Split Day ' || v_curr_date || ')'
                );
            END IF;
            
            -- C. Create Activities (Outside sleep hours)
            IF v_curr_date = v_start_date THEN
                 INSERT INTO public.app_activities (
                    session_id, user_id, app_name, start_time, end_time, start_time_utc, end_time_utc, duration_seconds
                ) VALUES 
                (v_session_id, target_user_id, 'Terminal', v_sess_start, v_sess_start + INTERVAL '60 minutes', 
                 v_sess_start AT TIME ZONE 'UTC', (v_sess_start + INTERVAL '60 minutes') AT TIME ZONE 'UTC', 3600);
            END IF;
            
            IF v_curr_date = v_end_date THEN
                 INSERT INTO public.app_activities (
                    session_id, user_id, app_name, start_time, end_time, start_time_utc, end_time_utc, duration_seconds
                ) VALUES 
                (v_session_id, target_user_id, 'Slack', v_sleep_end, v_sess_end, 
                 v_sleep_end AT TIME ZONE 'UTC', v_sess_end AT TIME ZONE 'UTC', 
                 EXTRACT(EPOCH FROM (v_sess_end - v_sleep_end))::INTEGER);
            END IF;

            v_curr_date := v_curr_date + 1;
        END LOOP;
    END;

    -- ========================================================================
    -- SCENARIO 3: Full Day Work-Sleep (Jan 15)
    -- ========================================================================
    v_check_in := curr_month_start + INTERVAL '14 days' + TIME '09:00:00'; -- Jan 15
    v_check_out := curr_month_start + INTERVAL '14 days' + TIME '17:00:00'; 
    
    INSERT INTO public.attendance_sessions (
        user_id, check_in_time, check_out_time, check_in_time_utc, check_out_time_utc,
        total_work_seconds, is_closed, check_in_source, check_out_source
    ) VALUES (
        target_user_id, v_check_in, v_check_out, 
        v_check_in AT TIME ZONE 'UTC', v_check_out AT TIME ZONE 'UTC',
        EXTRACT(EPOCH FROM (v_check_out - v_check_in))::INTEGER,
        true, 'script_generated', 'manual_checkout'
    ) RETURNING id INTO v_session_id;
    
    INSERT INTO public.work_during_sleep_periods (
        session_id, user_id, sleep_start_time, wake_time, 
        sleep_start_time_utc, wake_time_utc, duration_seconds, note
    ) VALUES (
        v_session_id, target_user_id, 
        v_check_in + INTERVAL '1 hour', 
        v_check_out - INTERVAL '1 hour', 
        (v_check_in + INTERVAL '1 hour') AT TIME ZONE 'UTC', 
        (v_check_out - INTERVAL '1 hour') AT TIME ZONE 'UTC',
        EXTRACT(EPOCH FROM (INTERVAL '6 hours'))::INTEGER,
        'Mid-day napping work'
    );

    -- ========================================================================
    -- FINALIZATION
    -- ========================================================================
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'refresh_monthly_summary_cache') THEN
        PERFORM public.refresh_monthly_summary_cache();
    END IF;

    RAISE NOTICE 'Refined Fake Data Generation Complete!';
END $$;
