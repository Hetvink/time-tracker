-- ============================================================================
-- TIME TRAK - FINAL MONTHLY SUMMARY MATERIALIZED VIEW (NET WORK FIX)
-- ============================================================================
-- This version addresses:
-- 1. Net Work Calculation: Ensure breaks are robustly subtracted.
--    (Removed broad filters that might exclude valid breaks).
-- 2. "IST" timezone ambiguity (mapped to Asia/Kolkata).
-- 3. Visual clamping of midnight checkout to 23:59:59.
--
-- Version: 10.0 - Final Net Work Fix
-- Requires: PostgreSQL 14+ (for multirange support)
-- ============================================================================

-- ============================================================================
-- PART 1: HELPER FUNCTIONS
-- ============================================================================

-- Helper: Safe conversion of UTC timestamp to Local Timestamp using timezone name
-- Includes robust fallback logic.
CREATE OR REPLACE FUNCTION public.get_local_timestamp_robust(
    p_utc_ts TIMESTAMPTZ, 
    p_tz TEXT,
    p_local_ts_hint TIMESTAMPTZ -- Provide check_in_time column as hint
)
RETURNS TIMESTAMP AS $$
DECLARE
    v_tz_name TEXT := p_tz;
    v_offset INTERVAL;
BEGIN
    If p_utc_ts IS NULL THEN
        RETURN NULL;
    END IF;

    -- 1. Handle "IST" ambiguity (Common in Flutter/Dart)
    IF v_tz_name = 'IST' THEN
        v_tz_name := 'Asia/Kolkata';
    END IF;

    -- 2. Try simple timezone conversion
    BEGIN
        IF v_tz_name IS NOT NULL AND v_tz_name != '' THEN
             RETURN p_utc_ts AT TIME ZONE v_tz_name;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        -- invalid timezone name, proceed to fallback
    END;

    -- 3. Fallback: Check if p_local_ts_hint looks like "Wall Clock stored as UTC"
    -- If the difference is significant (> 5 min), assume hint holds local time
    -- We compare the timestamp values at UTC.
    IF p_local_ts_hint IS NOT NULL THEN
        v_offset := p_local_ts_hint - p_utc_ts;
        IF ABS(EXTRACT(EPOCH FROM v_offset)) > 300 THEN
             -- Found an offset! Apply it to p_utc_ts manually
             -- (p_utc_ts + v_offset) gives the local wall clock as a TIMESTAMPTZ
             -- We want TIMESTAMP without time zone (local wall clock)
             -- Casting to TIMESTAMP drops offset, effectively returning wall clock
             RETURN (p_utc_ts + v_offset)::timestamp;
        END IF;
    END IF;

    -- 4. Ultimate Fallback: UTC
    RETURN p_utc_ts AT TIME ZONE 'UTC';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ----------------------------------------------------------------------------
-- Function: get_daily_work_seconds_local_final
-- Purpose: Calculate total effective work time for a specific LOCAL date.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_daily_work_seconds_local_final(
    p_user_id UUID,
    p_local_date DATE
)
RETURNS INTEGER AS $$
DECLARE
    v_start_of_day TIMESTAMP;
    v_end_of_day TIMESTAMP;
    v_sessions_multirange tsmultirange;
    v_breaks_multirange tsmultirange;
    v_effective_multirange tsmultirange;
BEGIN
    -- Define day boundaries in LOCAL TIME (timestamp without time zone)
    v_start_of_day := p_local_date::timestamp;
    v_end_of_day := v_start_of_day + INTERVAL '1 day';

    -- 1. Aggregate all session time ranges CLAMPED to this LOCAL day
    SELECT COALESCE(
        range_agg(
            CASE 
                WHEN GREATEST(public.get_local_timestamp_robust(check_in_time_utc, original_timezone, check_in_time), v_start_of_day) < 
                     LEAST(
                        COALESCE(
                            public.get_local_timestamp_robust(check_out_time_utc, original_timezone, check_out_time),
                            -- Calculate local "NOW" using inferred offset
                            public.get_local_timestamp_robust(NOW(), original_timezone, check_in_time + (NOW() - check_in_time_utc))
                        ), 
                        v_end_of_day
                     )
                THEN
                    tsrange(
                        GREATEST(public.get_local_timestamp_robust(check_in_time_utc, original_timezone, check_in_time), v_start_of_day),
                        LEAST(
                            COALESCE(
                                public.get_local_timestamp_robust(check_out_time_utc, original_timezone, check_out_time),
                                public.get_local_timestamp_robust(NOW(), original_timezone, check_in_time + (NOW() - check_in_time_utc))
                            ), 
                            v_end_of_day
                        ),
                        '[)' -- inclusive start, exclusive end
                    )
                ELSE NULL
            END
        ),
        '{}'::tsmultirange
    )
    INTO v_sessions_multirange
    FROM public.attendance_sessions
    WHERE user_id = p_user_id
      AND is_deleted = false
      -- Broad overlapping check (UTC)
      AND check_in_time_utc < (v_end_of_day AT TIME ZONE 'UTC') + INTERVAL '1 day' 
      AND (check_out_time_utc IS NULL OR check_out_time_utc > (v_start_of_day AT TIME ZONE 'UTC') - INTERVAL '1 day');

    -- 2. Aggregate all break time ranges linked to these sessions, CLAMPED to this LOCAL day
    SELECT COALESCE(
        range_agg(
            CASE 
                WHEN GREATEST(public.get_local_timestamp_robust(bp.break_start_time_utc, s.original_timezone, bp.break_start_time), v_start_of_day) <
                     LEAST(
                        COALESCE(
                            public.get_local_timestamp_robust(bp.break_end_time_utc, s.original_timezone, bp.break_end_time),
                            public.get_local_timestamp_robust(NOW(), s.original_timezone, s.check_in_time + (NOW() - s.check_in_time_utc))
                        ), 
                        v_end_of_day
                     )
                THEN
                    tsrange(
                        GREATEST(public.get_local_timestamp_robust(bp.break_start_time_utc, s.original_timezone, bp.break_start_time), v_start_of_day),
                        LEAST(
                            COALESCE(
                                public.get_local_timestamp_robust(bp.break_end_time_utc, s.original_timezone, bp.break_end_time),
                                public.get_local_timestamp_robust(NOW(), s.original_timezone, s.check_in_time + (NOW() - s.check_in_time_utc))
                            ), 
                            v_end_of_day
                        ),
                        '[)'
                    )
                ELSE NULL
            END
        ),
        '{}'::tsmultirange
    )
    INTO v_breaks_multirange
    FROM public.break_periods bp
    JOIN public.attendance_sessions s ON bp.session_id = s.id
    WHERE s.user_id = p_user_id
      AND s.is_deleted = false
      AND bp.is_deleted = false
      -- Use Local Time overlap check for precision (filtering done by range_agg CASE mostly)
      -- Removed risky UTC filters
      ;

    -- 3. Subtract breaks from sessions to get effective (NET) work time
    v_effective_multirange := v_sessions_multirange - v_breaks_multirange;

    -- 4. Calculate total duration in seconds
    RETURN (
        SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (upper(rng) - lower(rng)))), 0)::INTEGER
        FROM unnest(v_effective_multirange) AS rng
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- ----------------------------------------------------------------------------
-- Function: get_daily_sleep_seconds_local_final
-- Purpose: Calculate total work time during sleep (LOCAL TZ AWARE)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_daily_sleep_seconds_local_final(
    p_user_id UUID,
    p_local_date DATE
)
RETURNS INTEGER AS $$
DECLARE
    v_start_of_day TIMESTAMP;
    v_end_of_day TIMESTAMP;
    v_sleep_multirange tsmultirange;
BEGIN
    v_start_of_day := p_local_date::timestamp;
    v_end_of_day := v_start_of_day + INTERVAL '1 day';

    SELECT COALESCE(
        range_agg(
            CASE 
                WHEN GREATEST(public.get_local_timestamp_robust(w.sleep_start_time_utc, s.original_timezone, w.sleep_start_time), v_start_of_day) <
                     LEAST(public.get_local_timestamp_robust(w.wake_time_utc, s.original_timezone, w.wake_time), v_end_of_day)
                THEN
                    tsrange(
                        GREATEST(public.get_local_timestamp_robust(w.sleep_start_time_utc, s.original_timezone, w.sleep_start_time), v_start_of_day),
                        LEAST(public.get_local_timestamp_robust(w.wake_time_utc, s.original_timezone, w.wake_time), v_end_of_day),
                        '[)'
                    )
                ELSE NULL
            END
        ),
        '{}'::tsmultirange
    )
    INTO v_sleep_multirange
    FROM public.work_during_sleep_periods w
    JOIN public.attendance_sessions s ON w.session_id = s.id
    WHERE s.user_id = p_user_id
      AND s.is_deleted = false
      AND w.is_deleted = false
      -- Removed strict filtering to rely on range construction
      ;

    RETURN (
        SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (upper(rng) - lower(rng)))), 0)::INTEGER
        FROM unnest(v_sleep_multirange) AS rng
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- ----------------------------------------------------------------------------
-- Function: get_daily_break_seconds_local_final
-- Purpose: Calculate total break time (LOCAL TZ AWARE)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_daily_break_seconds_local_final(
    p_user_id UUID,
    p_local_date DATE
)
RETURNS INTEGER AS $$
DECLARE
    v_start_of_day TIMESTAMP;
    v_end_of_day TIMESTAMP;
    v_breaks_multirange tsmultirange;
BEGIN
    v_start_of_day := p_local_date::timestamp;
    v_end_of_day := v_start_of_day + INTERVAL '1 day';

    SELECT COALESCE(
        range_agg(
            CASE 
                WHEN GREATEST(public.get_local_timestamp_robust(bp.break_start_time_utc, s.original_timezone, bp.break_start_time), v_start_of_day) <
                     LEAST(
                        COALESCE(
                            public.get_local_timestamp_robust(bp.break_end_time_utc, s.original_timezone, bp.break_end_time),
                            public.get_local_timestamp_robust(NOW(), s.original_timezone, s.check_in_time + (NOW() - s.check_in_time_utc))
                        ), 
                        v_end_of_day
                     )
                THEN
                    tsrange(
                        GREATEST(public.get_local_timestamp_robust(bp.break_start_time_utc, s.original_timezone, bp.break_start_time), v_start_of_day),
                        LEAST(
                            COALESCE(
                                public.get_local_timestamp_robust(bp.break_end_time_utc, s.original_timezone, bp.break_end_time),
                                public.get_local_timestamp_robust(NOW(), s.original_timezone, s.check_in_time + (NOW() - s.check_in_time_utc))
                            ), 
                            v_end_of_day
                        ),
                        '[)'
                    )
                ELSE NULL
            END
        ),
        '{}'::tsmultirange
    )
    INTO v_breaks_multirange
    FROM public.break_periods bp
    JOIN public.attendance_sessions s ON bp.session_id = s.id
    WHERE s.user_id = p_user_id
      AND s.is_deleted = false
      AND bp.is_deleted = false
      -- Removed strict filtering
      ;

    RETURN (
        SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (upper(rng) - lower(rng)))), 0)::INTEGER
        FROM unnest(v_breaks_multirange) AS rng
    );
END;
$$ LANGUAGE plpgsql STABLE;


-- ============================================================================
-- 2. Materialized View Update (Using Per-Session Local Time)
-- ============================================================================

DROP MATERIALIZED VIEW IF EXISTS public.mv_monthly_summary CASCADE;

CREATE MATERIALIZED VIEW public.mv_monthly_summary AS
WITH base_sessions AS (
    SELECT
        s.id,
        s.user_id,
        s.original_timezone,
        -- Use Robust Helper function to get LOCAL timestamps
        public.get_local_timestamp_robust(s.check_in_time_utc, s.original_timezone, s.check_in_time) as check_in_local,
        COALESCE(
            public.get_local_timestamp_robust(s.check_out_time_utc, s.original_timezone, s.check_out_time),
            public.get_local_timestamp_robust(NOW(), s.original_timezone, s.check_in_time + (NOW() - s.check_in_time_utc))
        ) as check_out_local,
        s.check_in_time_utc
    FROM attendance_sessions s
    WHERE s.is_deleted = false
),
expanded_days AS (
    -- Expand into rows for every LOCAL DAY the session touches
    SELECT
        bs.user_id,
        d::date as work_date, -- Local Date
        EXTRACT(year FROM d)::integer as work_year,
        EXTRACT(month FROM d)::integer as work_month,
        bs.id as session_id,
        -- Clamped Local Times (for meta stats)
        GREATEST(bs.check_in_local, d) as day_check_in_local,
        LEAST(bs.check_out_local, d + INTERVAL '1 day') as day_check_out_local
    FROM base_sessions bs,
    LATERAL generate_series(
        bs.check_in_local::date,
        bs.check_out_local::date,
        '1 day'::interval
    ) d
),
distinct_day_keys AS (
    -- Get distinct user/local_day combinations
    SELECT DISTINCT user_id, work_year, work_month, work_date
    FROM expanded_days
),
day_calculations AS (
    -- Calculate precise totals for each LOCAL DAY using local time functions (TZ Aware)
    SELECT
        dd.user_id,
        dd.work_year,
        dd.work_month,
        dd.work_date,
        public.get_daily_work_seconds_local_final(dd.user_id, dd.work_date) as effective_total_work,
        public.get_daily_sleep_seconds_local_final(dd.user_id, dd.work_date) as effective_sleep_work,
        public.get_daily_break_seconds_local_final(dd.user_id, dd.work_date) as total_break_seconds
    FROM distinct_day_keys dd
),
daily_meta_stats AS (
    -- Determine session count and first/last check-in/out times (LOCAL)
    SELECT
        ed.user_id,
        ed.work_date,
        count(distinct ed.session_id) as session_count,
        min(ed.day_check_in_local) as first_check_in,
        -- VISUAL CLAMP: Ensure displayed check-out is strictly within the day
        -- Specifically, force 00:00:00 of next day to display as 23:59:59 of current day
        -- This avoids confusion where users see '12:00 AM' on Day 1.
        max(
            CASE 
                WHEN ed.day_check_out_local = (ed.work_date + INTERVAL '1 day')::timestamp THEN 
                     (ed.work_date + INTERVAL '1 day' - INTERVAL '1 second')::timestamp
                ELSE ed.day_check_out_local
            END
        ) as last_check_out
    FROM expanded_days ed
    GROUP BY ed.user_id, ed.work_date
),
activity_stats AS (
    SELECT
        ed.user_id,
        ed.work_date,
        count(distinct aa.id) as activity_count
    FROM app_activities aa
    JOIN expanded_days ed ON aa.session_id = ed.session_id
    WHERE aa.is_deleted = false
      -- Only count activities that started on this LOCAL day
      -- Using robust helper for activity start time
      AND (public.get_local_timestamp_robust(aa.start_time_utc, (SELECT original_timezone FROM attendance_sessions WHERE id = aa.session_id), aa.start_time))::date = ed.work_date
    GROUP BY ed.user_id, ed.work_date
)
SELECT
    dc.user_id,
    dc.work_year as year,
    dc.work_month as month,
    dc.work_date as date,
    
    COALESCE(dms.session_count, 0)::integer as session_count,
    
    -- Total Work (Local Day)
    dc.effective_total_work::integer as total_work_seconds,
    
    -- Normal Work
    GREATEST(0, dc.effective_total_work - dc.effective_sleep_work)::integer as normal_work_seconds,
    
    -- Sleep Work
    dc.effective_sleep_work::integer as total_work_during_sleep_seconds,
    -- Break Time
    dc.total_break_seconds::integer as total_break_seconds,
    
    COALESCE(as_stats.activity_count, 0)::integer as activity_count,
    
    -- Return Local timestamps as ISO strings (casted back to text/timestamp if needed)
    dms.first_check_in,
    dms.last_check_out,
    
    now() as computed_at
FROM day_calculations dc
LEFT JOIN daily_meta_stats dms ON dc.user_id = dms.user_id AND dc.work_date = dms.work_date
LEFT JOIN activity_stats as_stats ON dc.user_id = as_stats.user_id AND dc.work_date = as_stats.work_date;

-- ============================================================================
-- 3. Create Unique Index
-- ============================================================================

CREATE UNIQUE INDEX idx_mv_monthly_summary_lookup
ON public.mv_monthly_summary(user_id, year, month, date);

-- ============================================================================
-- 4. Refresh Function
-- ============================================================================

DROP FUNCTION IF EXISTS public.refresh_monthly_summary_cache();

CREATE OR REPLACE FUNCTION public.refresh_monthly_summary_cache()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_monthly_summary;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. Permissions
-- ============================================================================
GRANT SELECT ON public.mv_monthly_summary TO authenticated, anon;
