-- 20240607000000_create_materialized_views.sql
-- Prerequisites:
--   - All tables and view definitions from previous migrations
-- Purpose: Creates materialized views with proper transaction boundaries and advisory locks for performance

BEGIN;

-- 1. Relationship Strength Analytics Materialized View
SELECT pg_try_advisory_lock(hashtext('create_relationship_strength_mv'));

DO $$
BEGIN
  BEGIN
    CREATE MATERIALIZED VIEW IF NOT EXISTS public.relationship_strength_analytics_mv AS
    SELECT 
      r.id as relationship_id,
      r.from_person_id,
      r.to_person_id,
      rt.name as relationship_type,
      COUNT(i.id) as interaction_count,
      COALESCE(AVG(i.quality_score), 5) as avg_quality,
      COALESCE(AVG(i.reciprocity_score), 5) as avg_reciprocity,
      MAX(i.occurred_at) as last_interaction_at,
      CASE 
        WHEN MAX(i.occurred_at) IS NOT NULL THEN NOW() - MAX(i.occurred_at)
        ELSE NULL 
      END as time_since_last_interaction,
      (
        COALESCE(
          CASE 
            WHEN MAX(i.occurred_at) IS NULL THEN 1 
            WHEN NOW() - MAX(i.occurred_at) < INTERVAL '7 days' THEN 10
            WHEN NOW() - MAX(i.occurred_at) < INTERVAL '30 days' THEN 7
            WHEN NOW() - MAX(i.occurred_at) < INTERVAL '90 days' THEN 4
            ELSE 1
          END, 1) + 
        COALESCE(
          CASE 
            WHEN COUNT(i.id) = 0 THEN 1 
            WHEN COUNT(i.id) > 20 THEN 10
            WHEN COUNT(i.id) > 10 THEN 7
            WHEN COUNT(i.id) > 5 THEN 4
            ELSE 1
          END, 1) + 
        COALESCE(AVG(i.quality_score), 5) 
      )/3.0 as strength_score
    FROM public.relationships r
    LEFT JOIN public.relationship_types rt ON r.relationship_type_id = rt.id
    LEFT JOIN public.interaction_participants ip_from ON r.from_person_id = ip_from.person_id
    LEFT JOIN public.interaction_participants ip_to ON r.to_person_id = ip_to.person_id
    LEFT JOIN public.interactions i ON ip_from.interaction_id = i.id AND ip_to.interaction_id = i.id AND i.id = ip_from.interaction_id
    WHERE r.status = 'active'
    GROUP BY r.id, r.from_person_id, r.to_person_id, rt.name;
    
    RAISE NOTICE 'Created relationship_strength_analytics_mv materialized view';
  EXCEPTION 
    WHEN duplicate_table THEN
      RAISE NOTICE 'Materialized view relationship_strength_analytics_mv already exists, skipping';
  END;
END $$;

-- Create index for the materialized view
DO $$
BEGIN
  BEGIN
    CREATE UNIQUE INDEX IF NOT EXISTS idx_relationship_strength_mv_relationship_id 
    ON public.relationship_strength_analytics_mv(relationship_id);
    
    CREATE INDEX IF NOT EXISTS idx_relationship_strength_mv_from_person_id 
    ON public.relationship_strength_analytics_mv(from_person_id);
    
    CREATE INDEX IF NOT EXISTS idx_relationship_strength_mv_to_person_id 
    ON public.relationship_strength_analytics_mv(to_person_id);
    
    CREATE INDEX IF NOT EXISTS idx_relationship_strength_mv_strength_score 
    ON public.relationship_strength_analytics_mv(strength_score);
  EXCEPTION 
    WHEN duplicate_table THEN
      RAISE NOTICE 'Indexes for relationship_strength_analytics_mv already exist, skipping';
  END;
END $$;

SELECT pg_advisory_unlock(hashtext('create_relationship_strength_mv'));

-- 2. Brotherhood Visibility Materialized View
SELECT pg_try_advisory_lock(hashtext('create_brotherhood_visibility_mv'));

DO $$
BEGIN
  BEGIN
    CREATE MATERIALIZED VIEW IF NOT EXISTS public.brotherhood_visibility_mv AS
    SELECT 
      p.id as person_id,
      p.first_name,
      p.last_name,
      home_ag.id as home_activity_id,
      home_ag.name as home_activity_name,
      home_ag.category as home_activity_category,
      visited_ag.id as visited_activity_id,
      visited_ag.name as visited_activity_name,
      visited_ag.category as visited_activity_category,
      COUNT(cgp.id) as visit_count,
      SUM(cgp.recognition_points) as total_recognition_points
    FROM public.people p
    JOIN public.person_activities pa ON p.id = pa.person_id AND pa.primary_activity = TRUE
    JOIN public.activity_groups home_ag ON pa.activity_group_id = home_ag.id
    JOIN public.cross_group_participations cgp ON p.id = cgp.person_id AND home_ag.id = cgp.home_activity_id
    JOIN public.activity_groups visited_ag ON cgp.visited_activity_id = visited_ag.id
    GROUP BY 
      p.id, p.first_name, p.last_name, 
      home_ag.id, home_ag.name, home_ag.category, 
      visited_ag.id, visited_ag.name, visited_ag.category;
      
    RAISE NOTICE 'Created brotherhood_visibility_mv materialized view';
  EXCEPTION 
    WHEN duplicate_table THEN
      RAISE NOTICE 'Materialized view brotherhood_visibility_mv already exists, skipping';
  END;
END $$;

-- Create index for the materialized view
DO $$
BEGIN
  BEGIN
    CREATE UNIQUE INDEX IF NOT EXISTS idx_brotherhood_visibility_mv_person_home_visited
    ON public.brotherhood_visibility_mv(person_id, home_activity_id, visited_activity_id);
    
    CREATE INDEX IF NOT EXISTS idx_brotherhood_visibility_mv_person_id 
    ON public.brotherhood_visibility_mv(person_id);
    
    CREATE INDEX IF NOT EXISTS idx_brotherhood_visibility_mv_home_activity_id 
    ON public.brotherhood_visibility_mv(home_activity_id);
    
    CREATE INDEX IF NOT EXISTS idx_brotherhood_visibility_mv_visited_activity_id 
    ON public.brotherhood_visibility_mv(visited_activity_id);
  EXCEPTION 
    WHEN duplicate_table THEN
      RAISE NOTICE 'Indexes for brotherhood_visibility_mv already exist, skipping';
  END;
END $$;

SELECT pg_advisory_unlock(hashtext('create_brotherhood_visibility_mv'));

-- 3. Mentor Relationship Health Materialized View
SELECT pg_try_advisory_lock(hashtext('create_mentor_relationship_health_mv'));

DO $$
BEGIN
  BEGIN
    CREATE MATERIALIZED VIEW IF NOT EXISTS public.mentor_relationship_health_mv AS
    SELECT
      r.id AS relationship_id,
      r.from_person_id AS mentor_id,
      pm.first_name AS mentor_first_name,
      pm.last_name AS mentor_last_name,
      r.to_person_id AS student_id,
      ps.first_name AS student_first_name,
      ps.last_name AS student_last_name,
      r.start_date,
      COALESCE(EXTRACT(YEAR FROM AGE(CURRENT_DATE, r.start_date)), 0) AS relationship_years,
      COUNT(DISTINCT i.id) AS total_interactions,
      COUNT(DISTINCT i.id) FILTER (WHERE i.occurred_at > (CURRENT_DATE - INTERVAL '90 days')) AS recent_interactions_90_days,
      COUNT(DISTINCT rm.milestone_id) AS total_milestones_achieved,
      (SELECT COUNT(*) FROM public.mentor_milestones mm_req WHERE mm_req.is_required = TRUE) AS total_required_milestones_overall,
      COUNT(DISTINCT rm.milestone_id) FILTER (WHERE mm.is_required = TRUE) AS required_milestones_achieved_count,
      CASE
        WHEN COUNT(DISTINCT i.id) FILTER (WHERE i.occurred_at > (CURRENT_DATE - INTERVAL '90 days')) = 0 THEN 'inactive'
        WHEN 
          (SELECT COUNT(mm_req.id) 
           FROM public.mentor_milestones mm_req 
           WHERE mm_req.is_required = TRUE 
             AND mm_req.typical_year <= COALESCE(EXTRACT(YEAR FROM AGE(CURRENT_DATE, r.start_date)), 0)
          ) > COUNT(DISTINCT rm.milestone_id) FILTER (WHERE mm.is_required = TRUE AND mm.typical_year <= COALESCE(EXTRACT(YEAR FROM AGE(CURRENT_DATE, r.start_date)), 0))
        THEN 'behind_required_milestones'
        ELSE 'healthy'
      END AS health_status
    FROM public.relationships r
    JOIN public.people pm ON r.from_person_id = pm.id
    JOIN public.people ps ON r.to_person_id = ps.id
    LEFT JOIN public.relationship_types rt ON r.relationship_type_id = rt.id
    LEFT JOIN public.interaction_participants ip_mentor ON r.from_person_id = ip_mentor.person_id
    LEFT JOIN public.interaction_participants ip_student ON r.to_person_id = ip_student.person_id
    LEFT JOIN public.interactions i ON ip_mentor.interaction_id = i.id AND ip_student.interaction_id = i.id AND i.id = ip_mentor.interaction_id
    LEFT JOIN public.relationship_milestones rm ON r.id = rm.relationship_id
    LEFT JOIN public.mentor_milestones mm ON rm.milestone_id = mm.id
    WHERE rt.name = 'mentor' AND r.status = 'active'
    GROUP BY 
      r.id, r.from_person_id, pm.first_name, pm.last_name, 
      r.to_person_id, ps.first_name, ps.last_name, r.start_date;
      
    RAISE NOTICE 'Created mentor_relationship_health_mv materialized view';
  EXCEPTION 
    WHEN duplicate_table THEN
      RAISE NOTICE 'Materialized view mentor_relationship_health_mv already exists, skipping';
  END;
END $$;

-- Create index for the materialized view
DO $$
BEGIN
  BEGIN
    CREATE UNIQUE INDEX IF NOT EXISTS idx_mentor_relationship_health_mv_relationship_id
    ON public.mentor_relationship_health_mv(relationship_id);
    
    CREATE INDEX IF NOT EXISTS idx_mentor_relationship_health_mv_mentor_id 
    ON public.mentor_relationship_health_mv(mentor_id);
    
    CREATE INDEX IF NOT EXISTS idx_mentor_relationship_health_mv_student_id 
    ON public.mentor_relationship_health_mv(student_id);
    
    CREATE INDEX IF NOT EXISTS idx_mentor_relationship_health_mv_health_status 
    ON public.mentor_relationship_health_mv(health_status);
  EXCEPTION 
    WHEN duplicate_table THEN
      RAISE NOTICE 'Indexes for mentor_relationship_health_mv already exist, skipping';
  END;
END $$;

SELECT pg_advisory_unlock(hashtext('create_mentor_relationship_health_mv'));

-- Apply RLS to materialized views
ALTER MATERIALIZED VIEW public.relationship_strength_analytics_mv ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.brotherhood_visibility_mv ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.mentor_relationship_health_mv ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for materialized views
CREATE POLICY "relationship_strength_mv_read_self" ON public.relationship_strength_analytics_mv
  FOR SELECT USING (
    -- People can view relationships they're part of
    from_person_id IN (SELECT id FROM people WHERE auth_id = auth.uid()) OR
    to_person_id IN (SELECT id FROM people WHERE auth_id = auth.uid()) OR
    -- Or if they're an admin
    EXISTS (
      SELECT 1 FROM people
      JOIN roles ON people.role_id = roles.id
      WHERE people.auth_id = auth.uid() AND (roles.name = 'admin' OR roles.name = 'staff')
    )
  );

CREATE POLICY "brotherhood_visibility_mv_read_self" ON public.brotherhood_visibility_mv
  FOR SELECT USING (
    -- People can view their own brotherhood visibility
    person_id IN (SELECT id FROM people WHERE auth_id = auth.uid()) OR
    -- Or if they're an admin
    EXISTS (
      SELECT 1 FROM people
      JOIN roles ON people.role_id = roles.id
      WHERE people.auth_id = auth.uid() AND (roles.name = 'admin' OR roles.name = 'staff')
    )
  );

CREATE POLICY "mentor_relationship_health_mv_read_self" ON public.mentor_relationship_health_mv
  FOR SELECT USING (
    -- People can view their own mentor relationship health
    mentor_id IN (SELECT id FROM people WHERE auth_id = auth.uid()) OR
    student_id IN (SELECT id FROM people WHERE auth_id = auth.uid()) OR
    -- Or if they're an admin
    EXISTS (
      SELECT 1 FROM people
      JOIN roles ON people.role_id = roles.id
      WHERE people.auth_id = auth.uid() AND (roles.name = 'admin' OR roles.name = 'staff')
    )
  );

COMMENT ON MATERIALIZED VIEW public.relationship_strength_analytics_mv IS 'Materialized view for analytics on relationship strength based on interactions.';
COMMENT ON MATERIALIZED VIEW public.brotherhood_visibility_mv IS 'Materialized view for analyzing cross-group participation and "brotherhood visibility".';
COMMENT ON MATERIALIZED VIEW public.mentor_relationship_health_mv IS 'Materialized view for health assessment of active mentor relationships.';

COMMIT; 