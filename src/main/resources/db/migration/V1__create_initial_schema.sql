
-- V1: Initial RelayForge schema

CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    key_hash VARCHAR(255) NOT NULL UNIQUE,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE endpoints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_key_id UUID NOT NULL REFERENCES api_keys(id),
    name VARCHAR(100) NOT NULL,
    url TEXT NOT NULL,
    signing_secret TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_endpoints_api_key
    ON endpoints(api_key_id);

CREATE TABLE endpoint_event_types (
    endpoint_id UUID NOT NULL REFERENCES endpoints(id)
        ON DELETE CASCADE,
    event_type VARCHAR(150) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (endpoint_id, event_type)
);

CREATE INDEX idx_endpoint_event_types_event_type
    ON endpoint_event_types(event_type, endpoint_id);

CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_key_id UUID NOT NULL REFERENCES api_keys(id),
    event_type VARCHAR(150) NOT NULL,
    idempotency_key VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_events_api_key_idempotency
        UNIQUE (api_key_id, idempotency_key)
);

CREATE TABLE deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id),
    endpoint_id UUID NOT NULL REFERENCES endpoints(id),

    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    attempt_count INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    lease_owner VARCHAR(255),
    lease_expires_at TIMESTAMPTZ,

    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_deliveries_event_endpoint
        UNIQUE (event_id, endpoint_id),

    CONSTRAINT chk_deliveries_status
        CHECK (status IN (
            'PENDING',
            'PROCESSING',
            'SUCCEEDED',
            'DEAD_LETTER'
        )),

    CONSTRAINT chk_deliveries_attempt_count
        CHECK (attempt_count >= 0)
);

CREATE INDEX idx_deliveries_pending
    ON deliveries(next_attempt_at, created_at)
    WHERE status = 'PENDING';

CREATE INDEX idx_deliveries_expired_leases
    ON deliveries(lease_expires_at)
    WHERE status = 'PROCESSING';

CREATE TABLE delivery_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_id UUID NOT NULL REFERENCES deliveries(id),
    attempt_number INTEGER NOT NULL,

    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMPTZ,

    response_status INTEGER,
    response_body_excerpt TEXT,
    error_message TEXT,
    duration_ms BIGINT,

    CONSTRAINT uq_delivery_attempt_number
        UNIQUE (delivery_id, attempt_number),

    CONSTRAINT chk_delivery_attempt_number
        CHECK (attempt_number > 0)
);
