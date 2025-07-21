-- Product database schema for auto-sync from app stores

-- Store products table
CREATE TABLE IF NOT EXISTS store_products (
    id SERIAL PRIMARY KEY,
    product_id VARCHAR(255) NOT NULL,
    platform VARCHAR(50) NOT NULL CHECK (platform IN ('app_store', 'google_play')),
    product_type VARCHAR(50) NOT NULL CHECK (product_type IN ('subscription', 'consumable', 'non_consumable')),
    title VARCHAR(255),
    description TEXT,
    price DECIMAL(10,2),
    currency VARCHAR(10),
    localized_price VARCHAR(50),
    subscription_period VARCHAR(20), -- ISO 8601 duration (P1M, P1Y, etc.)
    introductory_price DECIMAL(10,2),
    introductory_period VARCHAR(20),
    trial_period VARCHAR(20),
    family_sharing BOOLEAN DEFAULT FALSE,
    available BOOLEAN DEFAULT TRUE,
    last_synced TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    -- Composite unique constraint
    UNIQUE(product_id, platform)
);

-- Index for efficient lookups
CREATE INDEX IF NOT EXISTS idx_store_products_product_id ON store_products(product_id);
CREATE INDEX IF NOT EXISTS idx_store_products_platform ON store_products(platform);
CREATE INDEX IF NOT EXISTS idx_store_products_type ON store_products(product_type);
CREATE INDEX IF NOT EXISTS idx_store_products_available ON store_products(available);

-- User purchases table
CREATE TABLE IF NOT EXISTS user_purchases (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    product_id VARCHAR(255) NOT NULL,
    platform VARCHAR(50) NOT NULL CHECK (platform IN ('app_store', 'google_play')),
    transaction_id VARCHAR(255) UNIQUE NOT NULL,
    purchase_date TIMESTAMP NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(10) NOT NULL,
    status VARCHAR(50) DEFAULT 'verified' CHECK (status IN ('pending', 'verified', 'failed', 'refunded')),
    receipt_data TEXT, -- Store original receipt/token data
    verification_response JSONB, -- Store full verification response
    expires_date TIMESTAMP, -- For subscriptions
    auto_renew_status BOOLEAN DEFAULT TRUE, -- For subscriptions
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    -- Foreign key to store_products
    FOREIGN KEY (product_id, platform) REFERENCES store_products(product_id, platform)
);

-- Indexes for user purchases
CREATE INDEX IF NOT EXISTS idx_user_purchases_user_id ON user_purchases(user_id);
CREATE INDEX IF NOT EXISTS idx_user_purchases_product_id ON user_purchases(product_id);
CREATE INDEX IF NOT EXISTS idx_user_purchases_transaction_id ON user_purchases(transaction_id);
CREATE INDEX IF NOT EXISTS idx_user_purchases_status ON user_purchases(status);
CREATE INDEX IF NOT EXISTS idx_user_purchases_purchase_date ON user_purchases(purchase_date);

-- Sync history table for tracking sync operations
CREATE TABLE IF NOT EXISTS sync_history (
    id SERIAL PRIMARY KEY,
    platform VARCHAR(50) NOT NULL CHECK (platform IN ('app_store', 'google_play')),
    sync_type VARCHAR(50) NOT NULL CHECK (sync_type IN ('full', 'incremental')),
    products_synced INTEGER DEFAULT 0,
    products_updated INTEGER DEFAULT 0,
    products_added INTEGER DEFAULT 0,
    products_removed INTEGER DEFAULT 0,
    sync_status VARCHAR(50) DEFAULT 'success' CHECK (sync_status IN ('success', 'failed', 'partial')),
    error_message TEXT,
    sync_duration_ms INTEGER, -- Duration in milliseconds
    started_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP,
    
    -- Index for sync history
    CREATE INDEX IF NOT EXISTS idx_sync_history_platform ON sync_history(platform);
    CREATE INDEX IF NOT EXISTS idx_sync_history_started_at ON sync_history(started_at);
    CREATE INDEX IF NOT EXISTS idx_sync_history_status ON sync_history(sync_status);
);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers to automatically update updated_at
CREATE TRIGGER update_store_products_updated_at 
    BEFORE UPDATE ON store_products 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_purchases_updated_at 
    BEFORE UPDATE ON user_purchases 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column(); 