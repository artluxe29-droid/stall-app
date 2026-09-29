-- Optional: run once in the Cloudflare D1 console to keep the admin page fast with thousands of rows.
CREATE INDEX IF NOT EXISTS orders_status_created ON orders(status,created);
CREATE INDEX IF NOT EXISTS orders_status_updated ON orders(status,updated);
CREATE INDEX IF NOT EXISTS orders_buyer ON orders(buyer);
CREATE INDEX IF NOT EXISTS orders_seller ON orders(seller);
CREATE INDEX IF NOT EXISTS users_role_created ON users(role,created);
CREATE INDEX IF NOT EXISTS vendor_codes_created ON vendor_codes(created);
