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
  verified INTEGER NOT NULL DEFAULT 0,     -- paid verified-seller badge
  school_id INTEGER, state TEXT,           -- where they study or trade
  no_cfee INTEGER                          -- 1 = no Stall fee on their collections (partners)
);
CREATE TABLE IF NOT EXISTS sessions(h TEXT PRIMARY KEY, uid INTEGER NOT NULL, exp INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS attempts(k TEXT NOT NULL, t INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS attempts_k ON attempts(k,t);   -- rate limits (logins, sign-ups, uploads, payments)
CREATE TABLE IF NOT EXISTS vendor_codes(code TEXT PRIMARY KEY, active INTEGER NOT NULL DEFAULT 1, label TEXT, created INTEGER, used_by INTEGER, kind TEXT);  -- kind: 'vendor' (sign-up invite) or 'store' (free store)
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
  featured_until INTEGER,                  -- paid feature ends at this time (ms)
  school_id INTEGER, state TEXT,
  qty INTEGER NOT NULL DEFAULT 1, qty_left INTEGER,           -- stock: how many listed / still available
  review TEXT NOT NULL DEFAULT 'live', review_note TEXT       -- photo check: checking, review, live or rejected
);
-- Photos. lid > 0 is a listing id; lid < 0 is minus a store item id. data is either the image as a data URL,
-- or 'r2:<content-type>' when the image is stored in the R2 bucket (binding PHOTOS) under p/<lid>/<n>.
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
  featured_until INTEGER,
  school_id INTEGER, state TEXT,
  reach TEXT NOT NULL DEFAULT 'school', reach_until INTEGER    -- paid visibility: school, state or national
);
CREATE TABLE IF NOT EXISTS store_items(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sid INTEGER NOT NULL,
  title TEXT NOT NULL, price INTEGER NOT NULL, descr TEXT,
  avail INTEGER NOT NULL DEFAULT 1,
  n INTEGER NOT NULL DEFAULT 0,
  created INTEGER NOT NULL,
  qty_left INTEGER,                        -- NULL = no stock limit
  review TEXT NOT NULL DEFAULT 'live', review_note TEXT
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
  receipt TEXT, r_amount INTEGER, r_ref TEXT,
  bank_code TEXT, bank_ok INTEGER NOT NULL DEFAULT 0,  -- bank_ok=1: seller's account was checked, so the buyer can pay through Paystack
  fee INTEGER, paid_via TEXT,              -- Stall's sale fee (5%, max 2,000, on items only); paid_via 'paystack' when paid by split payment
  sub INTEGER,                             -- items total; amount = sub + delivery fee when delivered
  d_on INTEGER NOT NULL DEFAULT 0, d_fee INTEGER NOT NULL DEFAULT 0, d_note TEXT, pickup TEXT,  -- seller's delivery offer and pickup spot when ordered
  method TEXT, addr TEXT, dphone TEXT,     -- 'pickup' or 'delivery' (and where to), chosen at payment
  dstage TEXT, track TEXT,                 -- paid, packed, on_way / ready, done; track = JSON list of {s,t}
  pin_lat REAL, pin_lng REAL               -- meeting spot on the map: buyer's delivery pin, or seller's pickup pin
);
-- Live delivery tracking: only the latest point of whoever is moving, deleted when the trip ends.
CREATE TABLE IF NOT EXISTS trips(oid INTEGER PRIMARY KEY, who TEXT NOT NULL, lat REAL, lng REAL, acc REAL, spd REAL, t INTEGER, started INTEGER NOT NULL, eta INTEGER, eta_t INTEGER, here_t INTEGER, near INTEGER NOT NULL DEFAULT 0, arrived INTEGER NOT NULL DEFAULT 0);
-- Paystack subaccount for each payout bank account ('bank_code:acct_no'), made the first time a buyer pays that seller.
CREATE TABLE IF NOT EXISTS ps_subs(k TEXT PRIMARY KEY, code TEXT NOT NULL, name TEXT, created INTEGER);
CREATE TABLE IF NOT EXISTS order_items(oid INTEGER NOT NULL, kind TEXT NOT NULL, ref_id INTEGER NOT NULL, title TEXT, price INTEGER, q INTEGER NOT NULL DEFAULT 1);
-- Schools across Nigeria (seeded from lib/schools.js; active=0 means requested by a user, waiting for admin approval).
CREATE TABLE IF NOT EXISTS schools(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, short TEXT, state TEXT NOT NULL, kind TEXT, active INTEGER NOT NULL DEFAULT 1, created INTEGER);

CREATE TABLE IF NOT EXISTS admin_log(id INTEGER PRIMARY KEY AUTOINCREMENT, t INTEGER NOT NULL, uid INTEGER, who TEXT, kind TEXT, action TEXT, oid INTEGER, target TEXT, detail TEXT);
CREATE TABLE IF NOT EXISTS settings(k TEXT PRIMARY KEY, v TEXT);
-- Money Stall earns: kind 'store' (opening fee), 'boost' (featured listing/store), 'verify' (badge), 'reach', 'commission' (sale fee on an order). amount in naira.
-- Every Paystack payment is recorded here before the payer is sent to Paystack, then finished exactly once
-- by the return page or the Paystack webhook (done: 0 waiting, 2 finishing, 1 finished).
CREATE TABLE IF NOT EXISTS pending_pay(ref TEXT PRIMARY KEY, uid INTEGER NOT NULL, kind TEXT NOT NULL, data TEXT, amount INTEGER NOT NULL, label TEXT, created INTEGER NOT NULL, done INTEGER NOT NULL DEFAULT 0, result TEXT);
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

-- Seller ratings: one per completed order. users.rating_sum / rating_n hold the running totals.
CREATE TABLE IF NOT EXISTS reviews(id INTEGER PRIMARY KEY AUTOINCREMENT, oid INTEGER NOT NULL UNIQUE, seller INTEGER NOT NULL, buyer INTEGER NOT NULL, buyer_name TEXT, title TEXT, stars INTEGER NOT NULL, body TEXT, created INTEGER NOT NULL);
-- Seller payouts (one per released order): status queued, processing, paid or failed.
CREATE TABLE IF NOT EXISTS payouts(oid INTEGER PRIMARY KEY, seller INTEGER NOT NULL, amount INTEGER NOT NULL, ref TEXT, status TEXT NOT NULL, err TEXT, tries INTEGER NOT NULL DEFAULT 0, how TEXT, created INTEGER NOT NULL, updated INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS ps_recips(k TEXT PRIMARY KEY, code TEXT NOT NULL, created INTEGER);
-- In-app chat: one thread per buyer, seller and listing/store/order ('L12', 'S3', 'O9').
CREATE TABLE IF NOT EXISTS threads(id INTEGER PRIMARY KEY AUTOINCREMENT, buyer INTEGER NOT NULL, seller INTEGER NOT NULL, ref TEXT NOT NULL, title TEXT, last TEXT, last_at INTEGER, last_by INTEGER, b_seen INTEGER NOT NULL DEFAULT 0, s_seen INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL, UNIQUE(buyer,seller,ref));
CREATE TABLE IF NOT EXISTS msgs(id INTEGER PRIMARY KEY AUTOINCREMENT, tid INTEGER NOT NULL, uid INTEGER NOT NULL, body TEXT NOT NULL, t INTEGER NOT NULL);
