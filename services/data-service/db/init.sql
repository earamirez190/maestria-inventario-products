CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'general',
    price NUMERIC(12, 2) NOT NULL DEFAULT 0,
    stock INTEGER NOT NULL DEFAULT 0
);

INSERT INTO products (id, name, category, price, stock)
VALUES
    ('demo-1', 'Producto de demostración', 'general', 25.00, 10),
    ('demo-2', 'Producto observabilidad', 'infra', 99.00, 5)
ON CONFLICT (id) DO NOTHING;
