-- grab-it MVP Database Schema v1.0.0
-- Idempotent, additive, compatible with Supabase PostgreSQL
-- Run with: psql -f v1.0.0.sql
-- Forward migrations: v1.0.0 → v1.0.1 → v1.0.2 (ALTER TABLE, ADD COLUMN, etc.)
-- Full snapshots: v1.0.0 → v1.1.0 → v1.2.0 (pg_dump export)

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUMS (closed vocabularies)
-- ============================================================

DO $$ BEGIN
    CREATE TYPE listing_status AS ENUM ('available', 'claimed', 'confirmed', 'given');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE claim_action AS ENUM ('confirm', 'decline');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE report_category AS ENUM (
        'prohibited_item',
        'misleading',
        'spam_duplicate',
        'safety_concern',
        'expired_unavailable',
        'other'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE guideline_hit_level AS ENUM ('warning', 'suspend_24h', 'suspend_7d');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE consent_type AS ENUM ('analytics', 'sponsorship', 'data_resale');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE notification_trigger AS ENUM (
        'new_claim',
        'claim_confirmed',
        'claim_declined',
        'listing_expiring',
        'report_received',
        'guideline_hit',
        'moderation_decision'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE listing_category AS ENUM (
        'books_school',
        'clothing_accessories',
        'furniture_appliances',
        'food_pantry',
        'electronics_gadgets',
        'home_decor',
        'sports_outdoors',
        'others'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- CORE TABLES
-- ============================================================

-- 1. account: User identity (synced to owner only)
CREATE TABLE IF NOT EXISTS public.account (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    email         text NOT NULL UNIQUE,
    display_name  text,
    avatar_url    text,
    role          text NOT NULL DEFAULT 'contributor' CHECK (role IN ('sysadmin','admin','moderator','contributor')),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT account_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_account_email ON public.account (email);
CREATE INDEX IF NOT EXISTS idx_account_role ON public.account (role);

-- 2. credential: Secrets (hashed), synced to owner only
CREATE TABLE IF NOT EXISTS public.credential (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    account_uuid  uuid NOT NULL,
    provider      text NOT NULL CHECK (provider IN ('google')),
    provider_sub  text NOT NULL,  -- Google's 'sub' claim
    secret_hash   text,           -- For future password auth (not used in MVP)
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT credential_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_credential_account ON public.credential (account_uuid);
CREATE UNIQUE INDEX IF NOT EXISTS idx_credential_provider_sub ON public.credential (provider, provider_sub) WHERE archived_at IS NULL;

-- 3. workspace: Top-level container (barangay/community area)
CREATE TABLE IF NOT EXISTS public.workspace (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    name          text NOT NULL,                    -- Barangay/community name
    boundary      jsonb,                            -- GeoJSON polygon for map bounds
    centroid_lat  double precision,                 -- Barangay centroid for approximate location
    centroid_lng  double precision,
    owner_uuid    uuid NOT NULL,                    -- Creator's account uuid
    created_by    uuid,                             -- Server-stamped on insert
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT workspace_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_workspace_owner ON public.workspace (owner_uuid);
CREATE INDEX IF NOT EXISTS idx_workspace_centroid ON public.workspace (centroid_lat, centroid_lng);

-- 4. category: Fixed listing categories (MVP: 8 categories)
CREATE TABLE IF NOT EXISTS public.category (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    slug          listing_category NOT NULL UNIQUE, -- Enum value
    name          text NOT NULL,                    -- Display name
    icon          text,                             -- Icon identifier
    sort_order    integer NOT NULL DEFAULT 0,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT category_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_category_slug ON public.category (slug) WHERE archived_at IS NULL;

-- Seed fixed categories (idempotent)
INSERT INTO public.category (slug, name, icon, sort_order) VALUES
    ('books_school', 'Books & School Supplies', 'book', 1),
    ('clothing_accessories', 'Clothing & Accessories', 'shirt', 2),
    ('furniture_appliances', 'Furniture & Appliances', 'chair', 3),
    ('food_pantry', 'Food & Pantry', 'utensils', 4),
    ('electronics_gadgets', 'Electronics & Gadgets', 'smartphone', 5),
    ('home_decor', 'Home & Decor', 'home', 6),
    ('sports_outdoors', 'Sports & Outdoors', 'dumbbell', 7),
    ('others', 'Others', 'package', 8)
ON CONFLICT (slug) DO UPDATE SET
    name = EXCLUDED.name,
    icon = EXCLUDED.icon,
    sort_order = EXCLUDED.sort_order,
    updated_at = now(),
    archived_at = NULL;

-- 5. listing: Main item listing (core entity)
CREATE TABLE IF NOT EXISTS public.listing (
    id                    bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid                  uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    workspace_uuid        uuid NOT NULL,                          -- Denormalized for scoped pulls
    category_uuid         uuid NOT NULL,                          -- FK to category (by uuid)
    title                 text NOT NULL,
    description           text,
    status                listing_status NOT NULL DEFAULT 'available',
    approx_lat            double precision,                       -- Barangay centroid ±500m jitter
    approx_lng            double precision,
    exact_lat             double precision,                       -- Revealed only after claim confirm
    exact_lng             double precision,
    exact_address         text,                                   -- Revealed only after claim confirm
    contact_info          text,                                   -- Revealed only after claim confirm
    expiry_at             timestamptz NOT NULL,                   -- 1-168 hours from creation
    claimant_uuid         uuid,                                   -- Seeker who claimed (locked in)
    confirmed_at          timestamptz,                            -- When giver confirmed
    given_at              timestamptz,                            -- When marked as given
    created_by            uuid,                                   -- Server-stamped on insert
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    archived_at           timestamptz,
    CONSTRAINT listing_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_listing_workspace ON public.listing (workspace_uuid);
CREATE INDEX IF NOT EXISTS idx_listing_category ON public.listing (category_uuid);
CREATE INDEX IF NOT EXISTS idx_listing_status ON public.listing (status) WHERE archived_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_listing_expiry ON public.listing (expiry_at) WHERE archived_at IS NULL AND status = 'available';
CREATE INDEX IF NOT EXISTS idx_listing_claimant ON public.listing (claimant_uuid);
CREATE INDEX IF NOT EXISTS idx_listing_approx ON public.listing (approx_lat, approx_lng) WHERE archived_at IS NULL AND status = 'available';

-- 6. listing_image: Photos for listings (max 3 per listing)
CREATE TABLE IF NOT EXISTS public.listing_image (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    listing_uuid  uuid NOT NULL,
    storage_path  text NOT NULL,              -- Supabase Storage path (private bucket)
    mime_type     text NOT NULL CHECK (mime_type IN ('image/jpeg','image/webp')),
    size_bytes    integer NOT NULL CHECK (size_bytes <= 5242880), -- ≤5 MB
    width         integer,
    height        integer,
    sort_order    integer NOT NULL DEFAULT 0,
    blurhash      text,                       -- Blurred thumbnail for map/list views
    created_by    uuid,                       -- Server-stamped on insert
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT listing_image_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_listing_image_listing ON public.listing_image (listing_uuid);
CREATE UNIQUE INDEX IF NOT EXISTS idx_listing_image_live ON public.listing_image (listing_uuid, sort_order) WHERE archived_at IS NULL;

-- 7. claim: Claim flow tracking (separate from listing for audit trail)
CREATE TABLE IF NOT EXISTS public.claim (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    listing_uuid  uuid NOT NULL,
    seeker_uuid   uuid NOT NULL,              -- Contributor who claimed
    action        claim_action,               -- 'confirm' or 'decline' by giver
    acted_at      timestamptz,                -- When giver acted
    created_by    uuid,                       -- Server-stamped (seeker)
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT claim_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_claim_listing ON public.claim (listing_uuid);
CREATE INDEX IF NOT EXISTS idx_claim_seeker ON public.claim (seeker_uuid);
CREATE UNIQUE INDEX IF NOT EXISTS idx_claim_listing_live ON public.claim (listing_uuid) WHERE archived_at IS NULL AND action IS NULL;

-- 8. report: Reports on listings
CREATE TABLE IF NOT EXISTS public.report (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    listing_uuid  uuid NOT NULL,
    reporter_uuid uuid NOT NULL,
    category      report_category NOT NULL,
    description   text,                       -- Free text for 'other' category
    status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','reviewed','dismissed','action_taken')),
    reviewed_by   uuid,                       -- Moderator/admin who reviewed
    reviewed_at   timestamptz,
    created_by    uuid,                       -- Server-stamped (reporter)
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT report_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_report_listing ON public.report (listing_uuid);
CREATE INDEX IF NOT EXISTS idx_report_reporter ON public.report (reporter_uuid);
CREATE INDEX IF NOT EXISTS idx_report_status ON public.report (status) WHERE archived_at IS NULL;

-- 9. guideline_hit: Guideline hits system (3 strikes = suspend)
CREATE TABLE IF NOT EXISTS public.guideline_hit (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    account_uuid  uuid NOT NULL,              -- Contributor who received hit
    listing_uuid  uuid,                       -- Related listing (if applicable)
    report_uuid   uuid,                       -- Related report (if applicable)
    level         guideline_hit_level NOT NULL,
    reason        text NOT NULL,
    expires_at    timestamptz NOT NULL,       -- 90 days from creation
    applied_by    uuid,                       -- Server-stamped (moderator/admin)
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT guideline_hit_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_guideline_hit_account ON public.guideline_hit (account_uuid);
CREATE INDEX IF NOT EXISTS idx_guideline_hit_expires ON public.guideline_hit (expires_at) WHERE archived_at IS NULL;

-- 10. consent: User consent records
CREATE TABLE IF NOT EXISTS public.consent (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    account_uuid  uuid NOT NULL,
    type          consent_type NOT NULL,
    granted       boolean NOT NULL,           -- true = opt-in, false = opt-out
    purpose       text,                       -- Per-purpose granularity for analytics
    sponsor_id    text,                       -- Per-sponsor granularity for sponsorship
    created_by    uuid,                       -- Server-stamped (account owner)
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT consent_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_consent_account_type ON public.consent (account_uuid, type, purpose, sponsor_id) WHERE archived_at IS NULL;

-- 11. notification: In-app notifications (MVP: in-app only)
CREATE TABLE IF NOT EXISTS public.notification (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    account_uuid  uuid NOT NULL,              -- Recipient
    trigger       notification_trigger NOT NULL,
    payload       jsonb NOT NULL,             -- { listing_uuid, claim_uuid, etc. }
    read_at       timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT notification_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_notification_account ON public.notification (account_uuid);
CREATE INDEX IF NOT EXISTS idx_notification_unread ON public.notification (account_uuid, read_at) WHERE archived_at IS NULL AND read_at IS NULL;

-- 12. sponsor: Sponsorship slots
CREATE TABLE IF NOT EXISTS public.sponsor (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    name          text NOT NULL,
    image_url     text NOT NULL,              -- Sponsor provided image
    headline      text NOT NULL,
    link_url      text NOT NULL,              -- External link
    is_active     boolean NOT NULL DEFAULT true,
    start_at      timestamptz,
    end_at        timestamptz,
    click_count   integer NOT NULL DEFAULT 0, -- Server-side click tracking
    created_by    uuid,                       -- Server-stamped (admin)
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT sponsor_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_sponsor_active ON public.sponsor (is_active, start_at, end_at) WHERE archived_at IS NULL;

-- 13. feature: Settings as rows (change without schema change)
CREATE TABLE IF NOT EXISTS public.feature (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    name          text NOT NULL UNIQUE,       -- e.g., 'max_photos_per_listing', 'default_expiry_hours'
    value         jsonb NOT NULL,             -- e.g., '3', '{"hours": 24}'
    description   text,
    created_by    uuid,                       -- Server-stamped (admin)
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT feature_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_feature_name ON public.feature (name) WHERE archived_at IS NULL;

-- Seed default features (idempotent)
INSERT INTO public.feature (name, value, description) VALUES
    ('max_photos_per_listing', '3', 'Maximum photos per listing'),
    ('max_photo_size_mb', '5', 'Maximum photo size in MB'),
    ('default_expiry_hours', '24', 'Default listing expiry in hours'),
    ('max_expiry_hours', '168', 'Maximum listing expiry in hours (7 days)'),
    ('min_expiry_hours', '1', 'Minimum listing expiry in hours'),
    ('location_jitter_meters', '500', 'Jitter radius for approximate location in meters'),
    ('search_default_radius_km', '5', 'Default search radius in kilometers'),
    ('search_max_radius_km', '20', 'Maximum search radius in kilometers'),
    ('sponsor_slot_ratio', '20', '1 sponsored slot per N organic listings'),
    ('guideline_hit_warning_threshold', '1', 'Hits before warning'),
    ('guideline_hit_suspend_24h_threshold', '2', 'Hits before 24h suspension'),
    ('guideline_hit_suspend_7d_threshold', '3', 'Hits before 7d suspension'),
    ('guideline_hit_expiry_days', '90', 'Days until guideline hits expire'),
    ('retention_days_post_expiry', '30', 'Days to retain given/archived listings'),
    ('report_retention_days', '90', 'Days to retain reports and moderation logs'),
    ('soft_delete_retention_days', '90', 'Days to retain soft-deleted rows'),
    ('analytics_aggregation_threshold', '10', 'Minimum users for aggregated analytics')
ON CONFLICT (name) DO UPDATE SET
    value = EXCLUDED.value,
    description = EXCLUDED.description,
    updated_at = now(),
    archived_at = NULL;

-- ============================================================
-- LINK TABLES (many-to-many relationships)
-- ============================================================

-- 14. workspace_member: Users in a workspace (barangay/community)
CREATE TABLE IF NOT EXISTS public.workspace_member (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    workspace_uuid uuid NOT NULL,
    account_uuid  uuid NOT NULL,
    role          text NOT NULL DEFAULT 'member' CHECK (role IN ('owner','admin','member')),
    created_by    uuid,                       -- Server-stamped
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT workspace_member_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_workspace_member_live ON public.workspace_member (workspace_uuid, account_uuid) WHERE archived_at IS NULL;

-- 15. listing_tag: Tags for listings (optional, for future filtering beyond categories)
CREATE TABLE IF NOT EXISTS public.listing_tag (
    id            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    uuid          uuid NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
    listing_uuid  uuid NOT NULL,
    tag           text NOT NULL,              -- Free-form tag
    created_by    uuid,                       -- Server-stamped
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    archived_at   timestamptz,
    CONSTRAINT listing_tag_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_listing_tag_listing ON public.listing_tag (listing_uuid);
CREATE UNIQUE INDEX IF NOT EXISTS idx_listing_tag_live ON public.listing_tag (listing_uuid, tag) WHERE archived_at IS NULL;

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE public.account ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credential ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing_image ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.claim ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guideline_hit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consent ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sponsor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feature ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_member ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing_tag ENABLE ROW LEVEL SECURITY;

-- Helper function for current user's account uuid
CREATE OR REPLACE FUNCTION public.current_account_uuid() RETURNS uuid
LANGUAGE sql STABLE AS $$
    SELECT auth.uid()::uuid;
$$;

-- account: users see only their own row; admins see all
CREATE POLICY account_select_own ON public.account FOR SELECT
    USING (uuid = current_account_uuid() OR EXISTS (SELECT 1 FROM public.account WHERE uuid = current_account_uuid() AND role IN ('sysadmin','admin')));

-- credential: owner only
CREATE POLICY credential_select_own ON public.credential FOR SELECT
    USING (account_uuid = current_account_uuid());

-- workspace: members can see; owner/admin can manage
CREATE POLICY workspace_select_member ON public.workspace FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.workspace_member WHERE workspace_uuid = workspace.uuid AND account_uuid = current_account_uuid() AND archived_at IS NULL));
CREATE POLICY workspace_modify_owner ON public.workspace FOR ALL
    USING (owner_uuid = current_account_uuid() OR EXISTS (SELECT 1 FROM public.account WHERE uuid = current_account_uuid() AND role IN ('sysadmin','admin')));

-- category: all authenticated users can read
CREATE POLICY category_select_all ON public.category FOR SELECT
    USING (auth.role() = 'authenticated');

-- listing: workspace members can see available/claimed/confirmed; giver/claimant see all statuses
CREATE POLICY listing_select_member ON public.listing FOR SELECT
    USING (
        archived_at IS NULL
        AND EXISTS (SELECT 1 FROM public.workspace_member WHERE workspace_uuid = listing.workspace_uuid AND account_uuid = current_account_uuid() AND archived_at IS NULL)
        AND (status IN ('available','claimed','confirmed') OR created_by = current_account_uuid() OR claimant_uuid = current_account_uuid())
    );
CREATE POLICY listing_insert_member ON public.listing FOR INSERT
    WITH CHECK (
        EXISTS (SELECT 1 FROM public.workspace_member WHERE workspace_uuid = listing.workspace_uuid AND account_uuid = current_account_uuid() AND archived_at IS NULL)
    );
CREATE POLICY listing_update_own ON public.listing FOR UPDATE
    USING (created_by = current_account_uuid() OR claimant_uuid = current_account_uuid())
    WITH CHECK (created_by = current_account_uuid() OR claimant_uuid = current_account_uuid());

-- listing_image: same as listing
CREATE POLICY listing_image_select ON public.listing_image FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.listing WHERE uuid = listing_image.listing_uuid AND archived_at IS NULL AND EXISTS (SELECT 1 FROM public.workspace_member WHERE workspace_uuid = listing.workspace_uuid AND account_uuid = current_account_uuid() AND archived_at IS NULL)));
CREATE POLICY listing_image_modify ON public.listing_image FOR ALL
    USING (EXISTS (SELECT 1 FROM public.listing WHERE uuid = listing_image.listing_uuid AND created_by = current_account_uuid()));

-- claim: seeker and giver can see
CREATE POLICY claim_select_parties ON public.claim FOR SELECT
    USING (seeker_uuid = current_account_uuid() OR EXISTS (SELECT 1 FROM public.listing WHERE uuid = claim.listing_uuid AND created_by = current_account_uuid()));
CREATE POLICY claim_insert_seeker ON public.claim FOR INSERT
    WITH CHECK (seeker_uuid = current_account_uuid());
CREATE POLICY claim_update_giver ON public.claim FOR UPDATE
    USING (EXISTS (SELECT 1 FROM public.listing WHERE uuid = claim.listing_uuid AND created_by = current_account_uuid()));

-- report: reporter, reported user, moderators, admins
CREATE POLICY report_select_involved ON public.report FOR SELECT
    USING (reporter_uuid = current_account_uuid() OR EXISTS (SELECT 1 FROM public.listing WHERE uuid = report.listing_uuid AND created_by = current_account_uuid()) OR EXISTS (SELECT 1 FROM public.account WHERE uuid = current_account_uuid() AND role IN ('sysadmin','admin','moderator')));
CREATE POLICY report_insert_reporter ON public.report FOR INSERT
    WITH CHECK (reporter_uuid = current_account_uuid());
CREATE POLICY report_update_moderator ON public.report FOR UPDATE
    USING (EXISTS (SELECT 1 FROM public.account WHERE uuid = current_account_uuid() AND role IN ('sysadmin','admin','moderator')));

-- guideline_hit: account owner, moderators, admins
CREATE POLICY guideline_hit_select_own ON public.guideline_hit FOR SELECT
    USING (account_uuid = current_account_uuid() OR EXISTS (SELECT 1 FROM public.account WHERE uuid = current_account_uuid() AND role IN ('sysadmin','admin','moderator')));
CREATE POLICY guideline_hit_modify_moderator ON public.guideline_hit FOR ALL
    USING (EXISTS (SELECT 1 FROM public.account WHERE uuid = current_account_uuid() AND role IN ('sysadmin','admin','moderator')));

-- consent: owner only
CREATE POLICY consent_select_own ON public.consent FOR SELECT
    USING (account_uuid = current_account_uuid());
CREATE POLICY consent_modify_own ON public.consent FOR ALL
    USING (account_uuid = current_account_uuid());

-- notification: recipient only
CREATE POLICY notification_select_own ON public.notification FOR SELECT
    USING (account_uuid = current_account_uuid());
CREATE POLICY notification_modify_own ON public.notification FOR ALL
    USING (account_uuid = current_account_uuid());

-- sponsor: all authenticated users can see active; admins manage
CREATE POLICY sponsor_select_active ON public.sponsor FOR SELECT
    USING (auth.role() = 'authenticated' AND is_active AND (start_at IS NULL OR start_at <= now()) AND (end_at IS NULL OR end_at >= now()) AND archived_at IS NULL);
CREATE POLICY sponsor_manage_admin ON public.sponsor FOR ALL
    USING (EXISTS (SELECT 1 FROM public.account WHERE uuid = current_account_uuid() AND role IN ('sysadmin','admin')));

-- feature: all authenticated users can read; admins manage
CREATE POLICY feature_select_all ON public.feature FOR SELECT
    USING (auth.role() = 'authenticated');
CREATE POLICY feature_manage_admin ON public.feature FOR ALL
    USING (EXISTS (SELECT 1 FROM public.account WHERE uuid = current_account_uuid() AND role IN ('sysadmin','admin')));

-- workspace_member: members can see; owner/admin manage
CREATE POLICY workspace_member_select ON public.workspace_member FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.workspace_member WHERE workspace_uuid = workspace_member.workspace_uuid AND account_uuid = current_account_uuid() AND archived_at IS NULL));
CREATE POLICY workspace_member_manage ON public.workspace_member FOR ALL
    USING (EXISTS (SELECT 1 FROM public.workspace WHERE uuid = workspace_member.workspace_uuid AND owner_uuid = current_account_uuid()) OR EXISTS (SELECT 1 FROM public.account WHERE uuid = current_account_uuid() AND role IN ('sysadmin','admin')));

-- listing_tag: same as listing
CREATE POLICY listing_tag_select ON public.listing_tag FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.listing WHERE uuid = listing_tag.listing_uuid AND archived_at IS NULL AND EXISTS (SELECT 1 FROM public.workspace_member WHERE workspace_uuid = listing.workspace_uuid AND account_uuid = current_account_uuid() AND archived_at IS NULL)));
CREATE POLICY listing_tag_modify ON public.listing_tag FOR ALL
    USING (EXISTS (SELECT 1 FROM public.listing WHERE uuid = listing_tag.listing_uuid AND created_by = current_account_uuid()));

-- ============================================================
-- TRIGGERS FOR updated_at (auto-bump on UPDATE)
-- ============================================================

CREATE OR REPLACE FUNCTION public.touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END $$;

-- Apply to all tables with updated_at
DO $$
DECLARE
    t text;
BEGIN
    FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename NOT IN ('spatial_ref_sys')
    LOOP
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = t AND column_name = 'updated_at') THEN
            EXECUTE format('DROP TRIGGER IF EXISTS trigger_%I_updated_at ON public.%I', t, t);
            EXECUTE format('CREATE TRIGGER trigger_%I_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at()', t, t);
        END IF;
    END LOOP;
END $$;

-- ============================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================

-- Live listings with category name and workspace name
CREATE OR REPLACE VIEW public.v_listing_live AS
SELECT
    l.uuid,
    l.workspace_uuid,
    w.name AS workspace_name,
    l.category_uuid,
    c.name AS category_name,
    c.slug AS category_slug,
    l.title,
    l.description,
    l.status,
    l.approx_lat,
    l.approx_lng,
    l.expiry_at,
    l.claimant_uuid,
    l.confirmed_at,
    l.given_at,
    l.created_by,
    l.created_at,
    l.updated_at
FROM public.listing l
JOIN public.workspace w ON w.uuid = l.workspace_uuid AND w.archived_at IS NULL
JOIN public.category c ON c.uuid = l.category_uuid AND c.archived_at IS NULL
WHERE l.archived_at IS NULL;

-- Active sponsors for feed injection
CREATE OR REPLACE VIEW public.v_sponsor_active AS
SELECT uuid, name, image_url, headline, link_url
FROM public.sponsor
WHERE is_active
  AND (start_at IS NULL OR start_at <= now())
  AND (end_at IS NULL OR end_at >= now())
  AND archived_at IS NULL;

-- Unread notification count per user
CREATE OR REPLACE VIEW public.v_notification_unread_count AS
SELECT account_uuid, count(*) AS unread_count
FROM public.notification
WHERE read_at IS NULL AND archived_at IS NULL
GROUP BY account_uuid;

-- ============================================================
-- GRANTS
-- ============================================================

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- ============================================================
-- END OF v1.0.0
-- ============================================================