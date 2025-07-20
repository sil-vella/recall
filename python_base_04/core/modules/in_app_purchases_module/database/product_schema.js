// MongoDB Schema for In-App Purchases Module
// Follows the existing modular pattern used in the system

// ========================================
// 1. STORE_PRODUCTS COLLECTION
// ========================================
print("🛍️ Creating store_products collection...");

db.createCollection("store_products");
db.store_products.createIndex({ "product_id": 1, "platform": 1 }, { unique: true });
db.store_products.createIndex({ "platform": 1 });
db.store_products.createIndex({ "product_type": 1 });
db.store_products.createIndex({ "available": 1 });
db.store_products.createIndex({ "last_synced": 1 });

// Insert sample products from both platforms
db.store_products.insertMany([
  // App Store Products
  {
    "_id": ObjectId("507f1f77bcf86cd799439101"),
    "product_id": "premium_feature_1",
    "platform": "app_store",
    "product_type": "non_consumable",
    "title": "Premium Feature 1",
    "description": "Unlock premium feature 1",
    "price": 0.99,
    "currency": "USD",
    "localized_price": "$0.99",
    "subscription_period": null,
    "introductory_price": null,
    "introductory_period": null,
    "trial_period": null,
    "family_sharing": false,
    "available": true,
    "last_synced": new Date(),
    "created_at": new Date(),
    "updated_at": new Date()
  },
  {
    "_id": ObjectId("507f1f77bcf86cd799439102"),
    "product_id": "subscription_monthly",
    "platform": "app_store",
    "product_type": "subscription",
    "title": "Premium Monthly",
    "description": "Monthly premium subscription",
    "price": 4.99,
    "currency": "USD",
    "localized_price": "$4.99",
    "subscription_period": "P1M",
    "introductory_price": 2.99,
    "introductory_period": "P1W",
    "trial_period": "P3D",
    "family_sharing": true,
    "available": true,
    "last_synced": new Date(),
    "created_at": new Date(),
    "updated_at": new Date()
  },
  {
    "_id": ObjectId("507f1f77bcf86cd799439103"),
    "product_id": "coins_100",
    "platform": "app_store",
    "product_type": "consumable",
    "title": "100 Coins",
    "description": "Get 100 coins",
    "price": 0.99,
    "currency": "USD",
    "localized_price": "$0.99",
    "subscription_period": null,
    "introductory_price": null,
    "introductory_period": null,
    "trial_period": null,
    "family_sharing": false,
    "available": true,
    "last_synced": new Date(),
    "created_at": new Date(),
    "updated_at": new Date()
  },
  
  // Google Play Products
  {
    "_id": ObjectId("507f1f77bcf86cd799439104"),
    "product_id": "premium_feature_1",
    "platform": "google_play",
    "product_type": "non_consumable",
    "title": "Premium Feature 1",
    "description": "Unlock premium feature 1",
    "price": 0.99,
    "currency": "USD",
    "localized_price": "$0.99",
    "subscription_period": null,
    "introductory_price": null,
    "introductory_period": null,
    "trial_period": null,
    "family_sharing": false,
    "available": true,
    "last_synced": new Date(),
    "created_at": new Date(),
    "updated_at": new Date()
  },
  {
    "_id": ObjectId("507f1f77bcf86cd799439105"),
    "product_id": "subscription_monthly",
    "platform": "google_play",
    "product_type": "subscription",
    "title": "Premium Monthly",
    "description": "Monthly premium subscription",
    "price": 4.99,
    "currency": "USD",
    "localized_price": "$4.99",
    "subscription_period": "P1M",
    "introductory_price": 2.99,
    "introductory_period": "P1W",
    "trial_period": null,
    "family_sharing": true,
    "available": true,
    "last_synced": new Date(),
    "created_at": new Date(),
    "updated_at": new Date()
  },
  {
    "_id": ObjectId("507f1f77bcf86cd799439106"),
    "product_id": "coins_100",
    "platform": "google_play",
    "product_type": "consumable",
    "title": "100 Coins",
    "description": "Get 100 coins",
    "price": 0.99,
    "currency": "USD",
    "localized_price": "$0.99",
    "subscription_period": null,
    "introductory_price": null,
    "introductory_period": null,
    "trial_period": null,
    "family_sharing": false,
    "available": true,
    "last_synced": new Date(),
    "created_at": new Date(),
    "updated_at": new Date()
  }
]);

print("✅ Store products collection created with " + db.store_products.countDocuments() + " products");

// ========================================
// 2. USER_PURCHASES COLLECTION
// ========================================
print("💳 Creating user_purchases collection...");

db.createCollection("user_purchases");
db.user_purchases.createIndex({ "user_id": 1 });
db.user_purchases.createIndex({ "product_id": 1 });
db.user_purchases.createIndex({ "transaction_id": 1 }, { unique: true });
db.user_purchases.createIndex({ "status": 1 });
db.user_purchases.createIndex({ "purchase_date": 1 });
db.user_purchases.createIndex({ "platform": 1 });

// Insert sample purchase records
db.user_purchases.insertMany([
  {
    "_id": ObjectId("507f1f77bcf86cd799439201"),
    "user_id": "507f1f77bcf86cd799439011", // John Doe
    "product_id": "premium_feature_1",
    "platform": "app_store",
    "transaction_id": "1000000000000001",
    "purchase_date": new Date("2024-03-01T10:30:00Z"),
    "amount": 0.99,
    "currency": "USD",
    "status": "verified",
    "receipt_data": "sample_receipt_data_1",
    "verification_response": {
      "valid": true,
      "platform": "app_store",
      "verified_at": new Date("2024-03-01T10:31:00Z")
    },
    "expires_date": null,
    "auto_renew_status": null,
    "created_at": new Date("2024-03-01T10:31:00Z"),
    "updated_at": new Date("2024-03-01T10:31:00Z")
  },
  {
    "_id": ObjectId("507f1f77bcf86cd799439202"),
    "user_id": "507f1f77bcf86cd799439012", // Jane Smith
    "product_id": "subscription_monthly",
    "platform": "app_store",
    "transaction_id": "1000000000000002",
    "purchase_date": new Date("2024-02-15T14:20:00Z"),
    "amount": 4.99,
    "currency": "USD",
    "status": "verified",
    "receipt_data": "sample_receipt_data_2",
    "verification_response": {
      "valid": true,
      "platform": "app_store",
      "verified_at": new Date("2024-02-15T14:21:00Z")
    },
    "expires_date": new Date("2024-03-15T14:20:00Z"),
    "auto_renew_status": true,
    "created_at": new Date("2024-02-15T14:21:00Z"),
    "updated_at": new Date("2024-02-15T14:21:00Z")
  },
  {
    "_id": ObjectId("507f1f77bcf86cd799439203"),
    "user_id": "507f1f77bcf86cd799439013", // Bob Wilson
    "product_id": "coins_100",
    "platform": "google_play",
    "transaction_id": "1000000000000003",
    "purchase_date": new Date("2024-03-01T16:45:00Z"),
    "amount": 0.99,
    "currency": "USD",
    "status": "verified",
    "receipt_data": "sample_receipt_data_3",
    "verification_response": {
      "valid": true,
      "platform": "google_play",
      "verified_at": new Date("2024-03-01T16:46:00Z")
    },
    "expires_date": null,
    "auto_renew_status": null,
    "created_at": new Date("2024-03-01T16:46:00Z"),
    "updated_at": new Date("2024-03-01T16:46:00Z")
  }
]);

print("✅ User purchases collection created with " + db.user_purchases.countDocuments() + " purchases");

// ========================================
// 3. SYNC_HISTORY COLLECTION
// ========================================
print("🔄 Creating sync_history collection...");

db.createCollection("sync_history");
db.sync_history.createIndex({ "platform": 1 });
db.sync_history.createIndex({ "started_at": 1 });
db.sync_history.createIndex({ "sync_status": 1 });

// Insert sample sync history
db.sync_history.insertMany([
  {
    "_id": ObjectId("507f1f77bcf86cd799439301"),
    "platform": "app_store",
    "sync_type": "full",
    "products_synced": 3,
    "products_updated": 2,
    "products_added": 1,
    "products_removed": 0,
    "sync_status": "success",
    "error_message": null,
    "sync_duration_ms": 1250,
    "started_at": new Date("2024-03-01T12:00:00Z"),
    "completed_at": new Date("2024-03-01T12:00:02Z")
  },
  {
    "_id": ObjectId("507f1f77bcf86cd799439302"),
    "platform": "google_play",
    "sync_type": "full",
    "products_synced": 3,
    "products_updated": 1,
    "products_added": 2,
    "products_removed": 0,
    "sync_status": "success",
    "error_message": null,
    "sync_duration_ms": 980,
    "started_at": new Date("2024-03-01T12:05:00Z"),
    "completed_at": new Date("2024-03-01T12:05:01Z")
  }
]);

print("✅ Sync history collection created with " + db.sync_history.countDocuments() + " records");

// ========================================
// 4. UPDATE USERS COLLECTION WITH IN-APP PURCHASES MODULE
// ========================================
print("👤 Adding in-app purchases module to existing users...");

// Add in-app purchases module data to existing users
db.users.updateMany(
  {},
  {
    "$set": {
      "modules.in_app_purchases": {
        "enabled": true,
        "active_purchases": [],
        "subscription_status": "none",
        "last_purchase_date": null,
        "total_spent": 0,
        "currency": "USD",
        "last_updated": new Date()
      }
    }
  }
);

print("✅ Updated users with in-app purchases module data");

// ========================================
// 5. UPDATE USER_MODULES COLLECTION
// ========================================
print("🔧 Adding in-app purchases module to module registry...");

db.user_modules.insertOne({
  "_id": ObjectId("507f1f77bcf86cd799439401"),
  "module_name": "in_app_purchases",
  "display_name": "In-App Purchases Module",
  "description": "In-app purchase and subscription management",
  "status": "active",
  "version": "1.0.0",
  "schema": {
    "enabled": "boolean",
    "active_purchases": "array",
    "subscription_status": "string",
    "last_purchase_date": "date",
    "total_spent": "number",
    "currency": "string",
    "last_updated": "date"
  },
  "created_at": new Date(),
  "updated_at": new Date()
});

print("✅ Added in-app purchases module to registry");

// ========================================
// FINAL SUMMARY
// ========================================
print("\n🎉 IN-APP PURCHASES DATABASE STRUCTURE SETUP COMPLETE!");
print("=====================================================");
print("Collections created/updated:");
print("- store_products: " + db.store_products.countDocuments() + " products");
print("- user_purchases: " + db.user_purchases.countDocuments() + " purchases");
print("- sync_history: " + db.sync_history.countDocuments() + " sync records");
print("- users: Updated with in-app purchases module data");
print("- user_modules: Added in-app purchases module to registry");
print("\n📊 Total documents: " + (db.store_products.countDocuments() + db.user_purchases.countDocuments() + db.sync_history.countDocuments()));
print("\n🔧 Features:");
print("- Auto-sync from App Store and Google Play");
print("- Purchase verification and tracking");
print("- Subscription management");
print("- Modular user data structure");
print("- Complete audit trail");
print("\n✅ In-App Purchases Module is ready for development!"); 