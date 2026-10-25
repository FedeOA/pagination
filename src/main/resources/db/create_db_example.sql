DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS product_categories;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS customer_profiles;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS seq;

CREATE TABLE customers (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    email       VARCHAR(150) NOT NULL UNIQUE,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- OneToOne: la FK es además UNIQUE
CREATE TABLE customer_profiles (
    id           BIGINT AUTO_INCREMENT PRIMARY KEY,
    customer_id  BIGINT NOT NULL UNIQUE,
    phone        VARCHAR(30),
    address      VARCHAR(200),
    birth_date   DATE,
    CONSTRAINT fk_profile_customer FOREIGN KEY (customer_id)
        REFERENCES customers(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE categories (
    id    BIGINT AUTO_INCREMENT PRIMARY KEY,
    name  VARCHAR(80) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE products (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(120) NOT NULL,
    price       DECIMAL(10,2) NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ManyToMany: tabla intermedia
CREATE TABLE product_categories (
    product_id   BIGINT NOT NULL,
    category_id  BIGINT NOT NULL,
    PRIMARY KEY (product_id, category_id),
    CONSTRAINT fk_pc_product  FOREIGN KEY (product_id)  REFERENCES products(id)   ON DELETE CASCADE,
    CONSTRAINT fk_pc_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ManyToOne hacia customers
CREATE TABLE orders (
    id           BIGINT AUTO_INCREMENT PRIMARY KEY,
    customer_id  BIGINT NOT NULL,
    status       VARCHAR(20) NOT NULL,
    total        DECIMAL(12,2) NOT NULL DEFAULT 0,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_orders_status CHECK (status IN ('NEW','PAID','SHIPPED','CANCELLED')),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(id)
) ENGINE=InnoDB;

-- OneToMany desde orders, ManyToOne hacia products
CREATE TABLE order_items (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id    BIGINT NOT NULL,
    product_id  BIGINT NOT NULL,
    quantity    INT NOT NULL,
    unit_price  DECIMAL(10,2) NOT NULL,
    CONSTRAINT chk_items_qty CHECK (quantity > 0),
    CONSTRAINT fk_items_order   FOREIGN KEY (order_id)   REFERENCES orders(id)   ON DELETE CASCADE,
    CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES products(id)
) ENGINE=InnoDB;

-- Índices acordes a filtro + orden de las skills (DESC real requiere MySQL 8+)
CREATE INDEX idx_orders_status_created_id ON orders (status, created_at DESC, id DESC);
CREATE INDEX idx_orders_customer ON orders (customer_id);
CREATE INDEX idx_order_items_order ON order_items (order_id);
CREATE INDEX idx_order_items_product ON order_items (product_id);
CREATE INDEX idx_product_categories_category ON product_categories (category_id);
CREATE INDEX idx_products_created_id ON products (created_at DESC, id DESC);
CREATE INDEX idx_customers_created_id ON customers (created_at DESC, id DESC);

-- ---------- Tabla auxiliar de números (1..50000) ----------
CREATE TABLE seq (n INT PRIMARY KEY);

INSERT INTO seq (n)
SELECT 1 + a.d + 10 * b.d + 100 * c.d + 1000 * e.d + 10000 * f.d AS n
FROM (SELECT 0 AS d UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
      UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) a
CROSS JOIN (SELECT 0 AS d UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
      UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) b
CROSS JOIN (SELECT 0 AS d UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
      UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) c
CROSS JOIN (SELECT 0 AS d UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
      UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) e
CROSS JOIN (SELECT 0 AS d UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4) f;

-- ---------- Datos de prueba ----------
INSERT INTO categories (name)
SELECT CONCAT('Category ', n) FROM seq WHERE n <= 20;

INSERT INTO customers (name, email, created_at)
SELECT CONCAT('Customer ', n),
       CONCAT('customer', n, '@test.com'),
       NOW() - INTERVAL FLOOR(RAND() * 365 * 24 * 3600) SECOND
FROM seq WHERE n <= 5000;

-- 1 perfil por cliente (OneToOne)
INSERT INTO customer_profiles (customer_id, phone, address, birth_date)
SELECT id,
       CONCAT('+34 6', LPAD(FLOOR(RAND() * 100000000), 8, '0')),
       CONCAT('Street ', id, ', City ', id % 50),
       DATE_ADD('1960-01-01', INTERVAL FLOOR(RAND() * 15000) DAY)
FROM customers;

INSERT INTO products (name, price, created_at)
SELECT CONCAT('Product ', n),
       ROUND(RAND() * 500 + 1, 2),
       NOW() - INTERVAL FLOOR(RAND() * 365 * 24 * 3600) SECOND
FROM seq WHERE n <= 1000;

-- 1 a 3 categorías por producto (ManyToMany)
INSERT IGNORE INTO product_categories (product_id, category_id)
SELECT p.id, 1 + ((p.id + k.k * 7) % 20)
FROM products p
JOIN (SELECT 0 AS k UNION SELECT 1 UNION SELECT 2) k
WHERE k.k = 0 OR RAND() < 0.5;

-- 50.000 pedidos (ManyToOne a customers)
INSERT INTO orders (customer_id, status, total, created_at)
SELECT 1 + FLOOR(RAND() * 5000),
       ELT(1 + FLOOR(RAND() * 4), 'NEW', 'PAID', 'SHIPPED', 'CANCELLED'),
       0,
       NOW() - INTERVAL FLOOR(RAND() * 365 * 24 * 3600) SECOND
FROM seq WHERE n <= 50000;

-- 1 a 5 líneas por pedido (OneToMany), producto elegido de forma determinista
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT o.id, p.id, 1 + FLOOR(RAND() * 4), p.price
FROM orders o
JOIN (SELECT 1 AS n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) j
  ON j.n <= 1 + (o.id % 5)
JOIN products p
  ON p.id = 1 + ((o.id * 31 + j.n * 97) % 1000);

-- Recalcular total del pedido
SET SQL_SAFE_UPDATES = 0;

UPDATE orders o
JOIN (SELECT order_id, SUM(quantity * unit_price) AS total
      FROM order_items GROUP BY order_id) s ON s.order_id = o.id
SET o.total = s.total;

SET SQL_SAFE_UPDATES = 1;

DROP TABLE seq;

ANALYZE TABLE customers, customer_profiles, products, categories,
              product_categories, orders, order_items;