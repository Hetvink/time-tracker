-- ============================================================================
-- Time Trak - Performance Optimization Functions and Views
-- ============================================================================
-- This file contains optimized database functions and views to improve
-- web application performance by reducing round-trips and computation on client
-- ============================================================================

-- ============================================================================
-- 1. FUNCTION: Get Daily Statistics (replaces multiple client-side queries)
-- ============================================================================
-- Returns aggregated daily statistics for a user in a single query
-- Includes: total work time, break time, session count, activity count

CREATE OR REPLACE FUNCTION public.get_daily_statistics(
    p_user_id UUID,
    p_date DATE
)
RETURNS TABLE (
    total_work_seconds INTEGER,
    total_break_seconds INTEGER,
    session_count BIGINT,
    activity_count BIGINT,
    first_check_in TIMESTAMPTZ,
    last_check_out TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(s.total_work_seconds), 0)::INTEGER as total_work_seconds,
        COALESCE(SUM(bp.duration_seconds), 0)::INTEGER as total_break_seconds,
        COUNT(DISTINCT s.id) as session_count,
        COUNT(DISTINCT aa.id) as activity_count,
        MIN(s.check_in_time_utc) as first_check_in,
        MAX(s.check_out_time_utc) as last_check_out
    FROM public.attendance_sessions s
    LEFT JOIN public.break_periods bp ON bp.session_id = s.id AND bp.is_deleted = false
    LEFT JOIN public.app_activities aa ON aa.session_id = s.id AND aa.is_deleted = false
    WHERE s.user_id = p_user_id
        AND s.is_deleted = false
        AND DATE(s.check_in_time_utc AT TIME ZONE 'UTC') = p_date;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 2. FUNCTION: Get Monthly Statistics (bulk monthly data)
-- ============================================================================
-- Returns daily statistics for an entire month in one query
-- Replaces sequential day-by-day queries

CREATE OR REPLACE FUNCTION public.get_monthly_statistics(
    p_user_id UUID,
    p_year INTEGER,
    p_month INTEGER
)
RETURNS TABLE (
    date DATE,
    total_work_seconds INTEGER,
    total_break_seconds INTEGER,
    session_count BIGINT,
    activity_count BIGINT,
    first_check_in TIMESTAMPTZ,
    last_check_out TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        DATE(s.check_in_time_utc AT TIME ZONE 'UTC') as date,
        COALESCE(SUM(s.total_work_seconds), 0)::INTEGER as total_work_seconds,
        COALESCE(SUM(bp.duration_seconds), 0)::INTEGER as total_break_seconds,
        COUNT(DISTINCT s.id) as session_count,
        COUNT(DISTINCT aa.id) as activity_count,
        MIN(s.check_in_time_utc) as first_check_in,
        MAX(s.check_out_time_utc) as last_check_out
    FROM public.attendance_sessions s
    LEFT JOIN public.break_periods bp ON bp.session_id = s.id AND bp.is_deleted = false
    LEFT JOIN public.app_activities aa ON aa.session_id = s.id AND aa.is_deleted = false
    WHERE s.user_id = p_user_id
        AND s.is_deleted = false
        AND EXTRACT(YEAR FROM s.check_in_time_utc AT TIME ZONE 'UTC') = p_year
        AND EXTRACT(MONTH FROM s.check_in_time_utc AT TIME ZONE 'UTC') = p_month
    GROUP BY DATE(s.check_in_time_utc AT TIME ZONE 'UTC')
    ORDER BY date DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 3. FUNCTION: Get Date Range Statistics
-- ============================================================================
-- Returns statistics for a custom date range

CREATE OR REPLACE FUNCTION public.get_date_range_statistics(
    p_user_id UUID,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ
)
RETURNS TABLE (
    total_work_seconds INTEGER,
    total_break_seconds INTEGER,
    session_count BIGINT,
    activity_count BIGINT,
    days_worked BIGINT,
    average_daily_seconds INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(s.total_work_seconds), 0)::INTEGER as total_work_seconds,
        COALESCE(SUM(bp.duration_seconds), 0)::INTEGER as total_break_seconds,
        COUNT(DISTINCT s.id) as session_count,
        COUNT(DISTINCT aa.id) as activity_count,
        COUNT(DISTINCT DATE(s.check_in_time_utc AT TIME ZONE 'UTC')) as days_worked,
        CASE
            WHEN COUNT(DISTINCT DATE(s.check_in_time_utc AT TIME ZONE 'UTC')) > 0
            THEN (COALESCE(SUM(s.total_work_seconds), 0) / COUNT(DISTINCT DATE(s.check_in_time_utc AT TIME ZONE 'UTC')))::INTEGER
            ELSE 0
        END as average_daily_seconds
    FROM public.attendance_sessions s
    LEFT JOIN public.break_periods bp ON bp.session_id = s.id AND bp.is_deleted = false
    LEFT JOIN public.app_activities aa ON aa.session_id = s.id AND aa.is_deleted = false
    WHERE s.user_id = p_user_id
        AND s.is_deleted = false
        AND s.check_in_time_utc >= p_start_date
        AND s.check_in_time_utc < p_end_date;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 4. FUNCTION: Get Top Applications (activity summary)
-- ============================================================================
-- Returns top applications by usage time for a date range

CREATE OR REPLACE FUNCTION public.get_top_applications(
    p_user_id UUID,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    app_name TEXT,
    total_duration_seconds INTEGER,
    activity_count BIGINT,
    last_used TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        aa.app_name,
        COALESCE(SUM(aa.duration_seconds), 0)::INTEGER as total_duration_seconds,
        COUNT(aa.id) as activity_count,
        MAX(aa.end_time_utc) as last_used
    FROM public.app_activities aa
    WHERE aa.user_id = p_user_id
        AND aa.is_deleted = false
        AND aa.start_time_utc >= p_start_date
        AND aa.start_time_utc < p_end_date
    GROUP BY aa.app_name
    ORDER BY total_duration_seconds DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 5. FUNCTION: Get Session Timeline (optimized day timeline)
-- ============================================================================
-- Returns complete session timeline with breaks and work periods for a day

CREATE OR REPLACE FUNCTION public.get_session_timeline(
    p_user_id UUID,
    p_date DATE
)
RETURNS TABLE (
    session_id UUID,
    check_in_time TIMESTAMPTZ,
    check_out_time TIMESTAMPTZ,
    total_work_seconds INTEGER,
    is_closed BOOLEAN,
    breaks JSONB,
    activities_summary JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id as session_id,
        s.check_in_time_utc as check_in_time,
        s.check_out_time_utc as check_out_time,
        s.total_work_seconds,
        s.is_closed,
        -- Aggregate breaks as JSON array
        COALESCE(
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'id', bp.id,
                    'start_time', bp.break_start_time_utc,
                    'end_time', bp.break_end_time_utc,
                    'duration_seconds', bp.duration_seconds,
                    'note', bp.note
                ) ORDER BY bp.break_start_time_utc
            )
            FROM public.break_periods bp
            WHERE bp.session_id = s.id AND bp.is_deleted = false),
            '[]'::jsonb
        ) as breaks,
        -- Aggregate activities summary
        COALESCE(
            (SELECT jsonb_build_object(
                'total_count', COUNT(*),
                'total_duration', COALESCE(SUM(aa.duration_seconds), 0),
                'top_apps', (
                    SELECT jsonb_agg(app_info ORDER BY duration DESC)
                    FROM (
                        SELECT
                            aa.app_name,
                            SUM(aa.duration_seconds) as duration
                        FROM public.app_activities aa
                        WHERE aa.session_id = s.id AND aa.is_deleted = false
                        GROUP BY aa.app_name
                        LIMIT 5
                    ) app_info
                )
            )
            FROM public.app_activities aa
            WHERE aa.session_id = s.id AND aa.is_deleted = false),
            jsonb_build_object('total_count', 0, 'total_duration', 0, 'top_apps', '[]'::jsonb)
        ) as activities_summary
    FROM public.attendance_sessions s
    WHERE s.user_id = p_user_id
        AND s.is_deleted = false
        AND DATE(s.check_in_time_utc AT TIME ZONE 'UTC') = p_date
    ORDER BY s.check_in_time_utc DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 6. MATERIALIZED VIEW: Monthly Summary Cache
-- ============================================================================
-- Pre-computed monthly summaries for faster dashboard loading
-- Refresh this view periodically (e.g., every hour or on-demand)

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_monthly_summary AS
SELECT
    s.user_id,
    EXTRACT(YEAR FROM s.check_in_time_utc AT TIME ZONE 'UTC')::INTEGER as year,
    EXTRACT(MONTH FROM s.check_in_time_utc AT TIME ZONE 'UTC')::INTEGER as month,
    DATE(s.check_in_time_utc AT TIME ZONE 'UTC') as date,
    COUNT(DISTINCT s.id) as session_count,
    COALESCE(SUM(s.total_work_seconds), 0)::INTEGER as total_work_seconds,
    COALESCE(SUM(bp.duration_seconds), 0)::INTEGER as total_break_seconds,
    COUNT(DISTINCT aa.id) as activity_count,
    MIN(s.check_in_time_utc) as first_check_in,
    MAX(s.check_out_time_utc) as last_check_out,
    NOW() as computed_at
FROM public.attendance_sessions s
LEFT JOIN public.break_periods bp ON bp.session_id = s.id AND bp.is_deleted = false
LEFT JOIN public.app_activities aa ON aa.session_id = s.id AND aa.is_deleted = false
WHERE s.is_deleted = false
GROUP BY
    s.user_id,
    EXTRACT(YEAR FROM s.check_in_time_utc AT TIME ZONE 'UTC'),
    EXTRACT(MONTH FROM s.check_in_time_utc AT TIME ZONE 'UTC'),
    DATE(s.check_in_time_utc AT TIME ZONE 'UTC');

-- Create unique index for fast lookups
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_monthly_summary_lookup
ON public.mv_monthly_summary(user_id, year, month, date);

-- ============================================================================
-- 7. FUNCTION: Refresh Monthly Summary Cache
-- ============================================================================
-- Call this function to refresh the materialized view

CREATE OR REPLACE FUNCTION public.refresh_monthly_summary_cache()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_monthly_summary;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 8. FUNCTION: Get Paginated Activities
-- ============================================================================
-- Returns paginated activities for infinite scroll

CREATE OR REPLACE FUNCTION public.get_paginated_activities(
    p_user_id UUID,
    p_session_id UUID DEFAULT NULL,
    p_offset INTEGER DEFAULT 0,
    p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    app_name TEXT,
    window_title TEXT,
    bundle_id TEXT,
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    duration_seconds INTEGER,
    session_id UUID,
    total_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH activity_data AS (
        SELECT
            aa.id,
            aa.app_name,
            aa.window_title,
            aa.bundle_id,
            aa.start_time_utc,
            aa.end_time_utc,
            aa.duration_seconds,
            aa.session_id,
            COUNT(*) OVER() as total_count
        FROM public.app_activities aa
        WHERE aa.user_id = p_user_id
            AND aa.is_deleted = false
            AND (p_session_id IS NULL OR aa.session_id = p_session_id)
        ORDER BY aa.start_time_utc DESC
        OFFSET p_offset
        LIMIT p_limit
    )
    SELECT * FROM activity_data;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 9. INDEX OPTIMIZATIONS for Performance
-- ============================================================================
-- Additional composite indexes for common query patterns

-- Index for daily statistics queries
CREATE INDEX IF NOT EXISTS idx_sessions_user_date
ON public.attendance_sessions(user_id, (DATE(check_in_time_utc AT TIME ZONE 'UTC')))
WHERE is_deleted = false;

-- Index for monthly queries
CREATE INDEX IF NOT EXISTS idx_sessions_user_year_month
ON public.attendance_sessions(
    user_id,
    (EXTRACT(YEAR FROM check_in_time_utc AT TIME ZONE 'UTC')),
    (EXTRACT(MONTH FROM check_in_time_utc AT TIME ZONE 'UTC'))
) WHERE is_deleted = false;

-- Index for activities with session
CREATE INDEX IF NOT EXISTS idx_activities_session_time
ON public.app_activities(session_id, start_time_utc)
WHERE is_deleted = false;

-- Index for activities by app name and user
CREATE INDEX IF NOT EXISTS idx_activities_user_app
ON public.app_activities(user_id, app_name, start_time_utc)
WHERE is_deleted = false;

-- ============================================================================
-- USAGE EXAMPLES
-- ============================================================================

-- Example 1: Get today's statistics
-- SELECT * FROM public.get_daily_statistics('user-uuid-here', CURRENT_DATE);

-- Example 2: Get monthly data (replaces 30 sequential queries with 1)
-- SELECT * FROM public.get_monthly_statistics('user-uuid-here', 2026, 1);

-- Example 3: Get date range stats
-- SELECT * FROM public.get_date_range_statistics(
--     'user-uuid-here',
--     '2026-01-01'::timestamptz,
--     '2026-02-01'::timestamptz
-- );

-- Example 4: Get top apps for today
-- SELECT * FROM public.get_top_applications(
--     'user-uuid-here',
--     CURRENT_DATE::timestamptz,
--     (CURRENT_DATE + INTERVAL '1 day')::timestamptz,
--     10
-- );

-- Example 5: Get complete session timeline for a day
-- SELECT * FROM public.get_session_timeline('user-uuid-here', CURRENT_DATE);

-- Example 6: Get paginated activities
-- SELECT * FROM public.get_paginated_activities('user-uuid-here', NULL, 0, 50);

-- Example 7: Use cached monthly summary (fastest)
-- SELECT * FROM public.mv_monthly_summary
-- WHERE user_id = 'user-uuid-here' AND year = 2026 AND month = 1;

-- Example 8: Refresh cache (run periodically or after bulk updates)
-- SELECT public.refresh_monthly_summary_cache();

-- ============================================================================
