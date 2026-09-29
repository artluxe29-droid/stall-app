-- Stall database schema (Cloudflare D1 / SQLite).
-- Matches every table and column the app in functions/api/[[path]].js uses.
-- Safe to run on a new database. On an existing one, CREATE ... IF NOT EXISTS skips tables that are already there
-- (it does not add missing columns to them).
-- admin_log, settings, payments, verify_requests and the featured/verified columns are also created automatically by the app the first time they are needed.

CREATE TABLE IF NOT EXISTS users(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  role TEXT NOT NULL,                      -- 'student' or 'vendor'
  name TEXT NOT NULL,
  matric TEXT UNIQUE,                      -- students only
  email TEXT,
  phone TEXT NOT NULL UNIQUE,              -- stored as 0XXXXXXXXXX
  place TEXT,
  biz TEXT,                                -- vendors: business name
  cat TEXT,                                -- vendors: category
  salt TEXT NOT NULL,
  pw TEXT NOT NULL,                        -- PBKDF2-SHA256 hash
  created INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',   -- 'active', 'pending' (vendor awaiting approval) or 'suspended'
  is_admin INTEGER NOT NULL DEFAULT 0,
  reviewer INTEGER NOT NULL DEFAULT 0,     -- can review payments
  bank_code TEXT, bank_name TEXT, acct_no TEXT, acct_name TEXT,
  bank_verified INTEGER,                   -- 0 = typed in by hand, waiting for an admin to confirm
  verified INTEGER NOT NULL DEFAULT 0      -- paid verified-seller badge
);
CREATE TABLE IF NOT EXISTS sessions(h TEXT PRIMARY KEY, uid INTEGER NOT NULL, exp INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS attempts(k TEXT NOT NULL, t INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS vendor_codes(code TEXT PRIMARY KEY, active INTEGER NOT NULL DEFAULT 1, label TEXT, created INTEGER, used_by INTEGER);
CREATE TABLE IF NOT EXISTS ver(id INTEGER PRIMARY KEY, n INTEGER NOT NULL DEFAULT 0);
INSERT OR IGNORE INTO ver(id,n) VALUES(1,0);

CREATE TABLE IF NOT EXISTS listings(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uid INTEGER NOT NULL,
  title TEXT NOT NULL, price INTEGER NOT NULL, cat TEXT, cond TEXT, spot TEXT, descr TEXT,
  seller TEXT, phone TEXT,
  n INTEGER NOT NULL DEFAULT 0,            -- number of photos
  created INTEGER NOT NULL,
  sold INTEGER NOT NULL DEFAULT 0,
  featured_until INTEGER                   -- paid feature ends at this time (ms)
);
-- Photos as data URLs. lid > 0 is a listing id; lid < 0 is minus a store item id.
CREATE TABLE IF NOT EXISTS photos(lid INTEGER NOT NULL, n INTEGER NOT NULL, data TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS stores(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uid INTEGER NOT NULL,
  name TEXT NOT NULL, emoji TEXT, cat TEXT, descr TEXT, spot TEXT, phone TEXT,
  bank TEXT, acct TEXT, acct_no TEXT, bank_code TEXT, acct_name TEXT, bank_verified INTEGER,
  isopen INTEGER NOT NULL DEFAULT 1,
  vendor INTEGER NOT NULL DEFAULT 0,
  ref TEXT,                                -- Paystack reference for the store fee
  created INTEGER NOT NULL,
  featured_until INTEGER
);
CREATE TABLE IF NOT EXISTS store_items(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sid INTEGER NOT NULL,
  title TEXT NOT NULL, price INTEGER NOT NULL, descr TEXT,
  avail INTEGER NOT NULL DEFAULT 1,
  n INTEGER NOT NULL DEFAULT 0,
  created INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS orders(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  buyer INTEGER NOT NULL, seller INTEGER NOT NULL,
  buyer_name TEXT, buyer_phone TEXT, seller_name TEXT, seller_phone TEXT,
  title TEXT NOT NULL, amount INTEGER NOT NULL,
  bank_name TEXT, acct_no TEXT, acct_name TEXT,
  status TEXT NOT NULL,                    -- pending, under_review, verified, released, rejected, expired
  deadline INTEGER NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL,
  code TEXT, code_used INTEGER,            -- release code
  note TEXT,                               -- why it needs review / was rejected
  receipt TEXT, r_amount INTEGER, r_ref TEXT
);
CREATE TABLE IF NOT EXISTS order_items(oid INTEGER NOT NULL, kind TEXT NOT NULL, ref_id INTEGER NOT NULL, title TEXT, price INTEGER);

CREATE TABLE IF NOT EXISTS admin_log(id INTEGER PRIMARY KEY AUTOINCREMENT, t INTEGER NOT NULL, uid INTEGER, who TEXT, kind TEXT, action TEXT, oid INTEGER, target TEXT, detail TEXT);
CREATE TABLE IF NOT EXISTS settings(k TEXT PRIMARY KEY, v TEXT);
-- Money Stall earns: kind 'store' (opening fee), 'boost' (featured listing/store), 'verify' (badge). amount in naira.
CREATE TABLE IF NOT EXISTS payments(ref TEXT PRIMARY KEY, uid INTEGER, kind TEXT, target TEXT, label TEXT, days INTEGER, amount INTEGER, created INTEGER);
CREATE INDEX IF NOT EXISTS payments_created ON payments(created);
-- Verified-badge requests: pending -> approved (then paid) or rejected.
CREATE TABLE IF NOT EXISTS verify_requests(uid INTEGER PRIMARY KEY, note TEXT, photo TEXT, status TEXT, reason TEXT, created INTEGER, updated INTEGER);

-- Indexes (same as indexes.sql)
CREATE INDEX IF NOT EXISTS admin_log_oid ON admin_log(oid);
CREATE INDEX IF NOT EXISTS admin_log_t ON admin_log(t);
CREATE INDEX IF NOT EXISTS orders_status_created ON orders(status,created);
CREATE INDEX IF NOT EXISTS orders_status_updated ON orders(status,updated);
CREATE INDEX IF NOT EXISTS orders_buyer ON orders(buyer);
CREATE INDEX IF NOT EXISTS orders_seller ON orders(seller);
CREATE INDEX IF NOT EXISTS users_role_created ON users(role,created);
CREATE INDEX IF NOT EXISTS vendor_codes_created ON vendor_codes(created);
CREATE INDEX IF NOT EXISTS listings_created ON listings(created);
CREATE INDEX IF NOT EXISTS listings_cat_created ON listings(cat,created);
CREATE INDEX IF NOT EXISTS listings_uid ON listings(uid);
CREATE INDEX IF NOT EXISTS photos_lid ON photos(lid,n);
CREATE INDEX IF NOT EXISTS order_items_oid ON order_items(oid);
