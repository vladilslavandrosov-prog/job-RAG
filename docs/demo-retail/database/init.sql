-- ТоргЛайн — демо-база для подключения платформы «Синапс.Инсайт» как живого источника данных
-- (в дополнение к файловому пакету в docs/demo-retail/dataset/).
-- Все компании, лица и цифры вымышлены. Данные согласованы с уже существующими
-- Word/Excel-файлами демо-пакета — это их структурированный, «подключаемый» эквивалент,
-- а не новый, отдельно придуманный набор фактов.
--
-- Запуск: psql -h <host> -U <user> -d <db> -f init.sql
-- Либо через docker-compose (см. docker-compose.yml рядом с этим файлом).

CREATE SCHEMA IF NOT EXISTS torgline;
SET search_path TO torgline;

-- =========================================================================
-- 1. Справочники: регионы, магазины
-- =========================================================================

CREATE TABLE regions (
    region_id   SERIAL PRIMARY KEY,
    region_name TEXT NOT NULL UNIQUE
);

CREATE TABLE stores (
    store_id   SERIAL PRIMARY KEY,
    store_code TEXT NOT NULL UNIQUE,           -- 'Магазин №14'
    city       TEXT NOT NULL,
    region_id  INT NOT NULL REFERENCES regions(region_id),
    format     TEXT NOT NULL DEFAULT 'супермаркет'
);

-- =========================================================================
-- 2. Поставщики и договоры
-- =========================================================================

CREATE TABLE suppliers (
    supplier_id       SERIAL PRIMARY KEY,
    name              TEXT NOT NULL,
    inn               TEXT NOT NULL,           -- sensitive: ИНН
    kpp               TEXT,                    -- sensitive: КПП
    ogrn              TEXT,                    -- sensitive: ОГРН
    legal_address     TEXT,                    -- sensitive: юр. адрес
    bank_name         TEXT,                    -- sensitive: банк
    bank_account      TEXT,                    -- sensitive: р/с
    corr_account      TEXT,                    -- sensitive: к/с
    bik               TEXT,                    -- sensitive: БИК
    contact_full_name TEXT,                    -- sensitive: ПДн контактного лица
    contact_phone     TEXT,                    -- sensitive: ПДн
    contact_email     TEXT                     -- sensitive: ПДн
);

CREATE TABLE contracts (
    contract_id                SERIAL PRIMARY KEY,
    supplier_id                INT NOT NULL REFERENCES suppliers(supplier_id),
    contract_number             TEXT NOT NULL UNIQUE,
    category                   TEXT NOT NULL,      -- 'Fresh', 'Techno'
    signed_date                DATE NOT NULL,
    valid_from                 DATE NOT NULL,
    valid_to                   DATE NOT NULL,
    payment_delay_days         INT NOT NULL,
    min_order_amount           NUMERIC(12,2),
    volume_discount_pct        NUMERIC(5,2),
    volume_discount_threshold  NUMERIC(12,2),
    delivery_frequency         TEXT,
    warranty_months            INT,               -- NULL, где гарантия не применима (Fresh)
    penalty_late_pct           NUMERIC(5,3),
    penalty_shortfall_pct      NUMERIC(5,3),
    responsible_manager        TEXT                -- sensitive: ПДн (ФИО сотрудника)
);

-- =========================================================================
-- 3. Товары (SKU)
-- =========================================================================

CREATE TABLE products (
    sku            TEXT PRIMARY KEY,
    name           TEXT NOT NULL,
    category_code  TEXT,
    category_name  TEXT,
    supplier_id    INT REFERENCES suppliers(supplier_id)
);

-- =========================================================================
-- 4. Продажи — две сетки агрегации, зеркалящие уже существующие xlsx:
--    по SKU за квартал (сеть в целом) и по магазинам за месяц (без разбивки по SKU).
--    Гранулярность «магазин × SKU × период» в исходных данных не публиковалась —
--    не сшиваем её искусственно, чтобы не придумывать цифры, которых нет.
-- =========================================================================

CREATE TABLE sales_sku_monthly (
    sale_id         BIGSERIAL PRIMARY KEY,
    sku             TEXT NOT NULL REFERENCES products(sku),
    period          DATE NOT NULL,               -- первое число месяца
    qty_sold        INT NOT NULL,
    purchase_price  NUMERIC(10,2) NOT NULL,       -- sensitive: закупочная цена
    retail_price    NUMERIC(10,2) NOT NULL,
    revenue         NUMERIC(14,2) GENERATED ALWAYS AS (qty_sold * retail_price) STORED,
    margin_rub      NUMERIC(14,2) GENERATED ALWAYS AS (qty_sold * (retail_price - purchase_price)) STORED,
    UNIQUE (sku, period)
);

CREATE TABLE sales_store_monthly (
    sale_id          BIGSERIAL PRIMARY KEY,
    store_id         INT NOT NULL REFERENCES stores(store_id),
    period           DATE NOT NULL,
    revenue          NUMERIC(14,2) NOT NULL,
    purchase_cost    NUMERIC(14,2) NOT NULL,      -- sensitive: закупочная стоимость
    margin_rub       NUMERIC(14,2) GENERATED ALWAYS AS (revenue - purchase_cost) STORED,  -- sensitive: маржа
    UNIQUE (store_id, period)
);

-- =========================================================================
-- 5. Остатки (снимок на дату)
-- =========================================================================

CREATE TABLE inventory_snapshots (
    snapshot_id      BIGSERIAL PRIMARY KEY,
    store_id         INT NOT NULL REFERENCES stores(store_id),
    sku              TEXT NOT NULL REFERENCES products(sku),
    snapshot_date    DATE NOT NULL,
    qty_on_hand      INT NOT NULL,
    avg_daily_sales  NUMERIC(6,2) NOT NULL,
    days_of_stock    NUMERIC(6,2) GENERATED ALWAYS AS (
                         CASE WHEN avg_daily_sales > 0 THEN qty_on_hand / avg_daily_sales END
                     ) STORED,
    UNIQUE (store_id, sku, snapshot_date)
);

-- =========================================================================
-- 6. Акции
-- =========================================================================

CREATE TABLE promotions (
    promotion_id    SERIAL PRIMARY KEY,
    promo_code      TEXT UNIQUE,
    name            TEXT NOT NULL,
    category_code   TEXT,
    date_from       DATE NOT NULL,
    date_to         DATE NOT NULL,
    mechanics       TEXT
);

CREATE TABLE promotion_skus (
    promotion_id  INT NOT NULL REFERENCES promotions(promotion_id),
    sku           TEXT NOT NULL REFERENCES products(sku),
    priority_rank INT,
    PRIMARY KEY (promotion_id, sku)
);

CREATE TABLE promotion_effectiveness (
    promotion_id               INT PRIMARY KEY REFERENCES promotions(promotion_id),
    revenue                    NUMERIC(14,2),
    avg_check                  NUMERIC(10,2),
    uplift_pct                 NUMERIC(6,4),
    loyalty_participation_pct  NUMERIC(6,4)
);

-- =========================================================================
-- 7. Клиенты и программа лояльности
-- =========================================================================

CREATE TABLE customers (
    customer_id   SERIAL PRIMARY KEY,
    full_name     TEXT NOT NULL,      -- sensitive: ПДн
    phone         TEXT,               -- sensitive: ПДн
    email         TEXT,               -- sensitive: ПДн
    loyalty_tier  TEXT NOT NULL DEFAULT 'Стандарт',
    card_number   TEXT                -- sensitive: ПДн/платёжный идентификатор
);

CREATE TABLE loyalty_transactions (
    transaction_id    BIGSERIAL PRIMARY KEY,
    customer_id       INT NOT NULL REFERENCES customers(customer_id),
    store_id          INT NOT NULL REFERENCES stores(store_id),
    receipt_number    TEXT NOT NULL,
    purchase_date     DATE NOT NULL,
    purchase_amount   NUMERIC(10,2) NOT NULL,
    points_earned     INT NOT NULL DEFAULT 0,
    points_redeemed   INT NOT NULL DEFAULT 0,
    points_balance    INT NOT NULL,
    note              TEXT
);

-- =========================================================================
-- 8. Претензии к поставщикам
-- =========================================================================

CREATE TABLE supplier_claims (
    claim_id              SERIAL PRIMARY KEY,
    supplier_id           INT NOT NULL REFERENCES suppliers(supplier_id),
    contract_id           INT REFERENCES contracts(contract_id),
    claim_date            DATE NOT NULL,
    claim_type            TEXT NOT NULL,   -- 'просрочка' | 'недопоставка' | 'качество'
    description           TEXT,
    penalty_amount        NUMERIC(10,2),
    compensation_amount   NUMERIC(10,2),
    resolution            TEXT
);

-- =========================================================================
-- 9. Сотрудники — опорная таблица для персон «Графа доступа» (сценарий 2)
-- =========================================================================

CREATE TABLE employees (
    employee_id  SERIAL PRIMARY KEY,
    full_name    TEXT NOT NULL,        -- sensitive: ПДн
    role         TEXT NOT NULL,        -- 'Директор магазина' | 'Региональный директор' | 'Финансист HQ' | 'Категорийный менеджер' | 'Маркетинг-аналитик'
    store_id     INT REFERENCES stores(store_id),    -- NULL, если роль не привязана к магазину
    region_id    INT REFERENCES regions(region_id),  -- NULL, если роль не привязана к региону
    phone        TEXT,                 -- sensitive: ПДн
    email        TEXT,                 -- sensitive: ПДн
    login        TEXT NOT NULL UNIQUE  -- логин для входа в платформу; НЕ маскировать — на нём строится сама привязка персон Графа доступа
);

-- =========================================================================
-- 10. Каталог чувствительных полей — опора для настройки масок AI Guard / Графа доступа
-- =========================================================================

CREATE TABLE data_sensitivity_catalog (
    table_name      TEXT NOT NULL,
    column_name     TEXT NOT NULL,
    sensitivity     TEXT NOT NULL,   -- 'pii' | 'financial' | 'contract_terms'
    note            TEXT,
    PRIMARY KEY (table_name, column_name)
);

-- =========================================================================
-- Данные
-- =========================================================================

INSERT INTO regions (region_name) VALUES
    ('Центральный'), ('Северо-Западный'), ('Приволжский'), ('Уральский'), ('Сибирский');

INSERT INTO stores (store_code, city, region_id, format) VALUES
    ('Магазин №14', 'Москва, ЮЗАО',     (SELECT region_id FROM regions WHERE region_name = 'Центральный'),      'супермаркет'),
    ('Магазин №22', 'Москва, СВАО',     (SELECT region_id FROM regions WHERE region_name = 'Центральный'),      'супермаркет'),
    ('Магазин №31', 'Санкт-Петербург',  (SELECT region_id FROM regions WHERE region_name = 'Северо-Западный'),  'супермаркет'),
    ('Магазин №08', 'Казань',           (SELECT region_id FROM regions WHERE region_name = 'Приволжский'),      'супермаркет'),
    ('Магазин №19', 'Екатеринбург',     (SELECT region_id FROM regions WHERE region_name = 'Уральский'),        'супермаркет'),
    ('Магазин №27', 'Новосибирск',      (SELECT region_id FROM regions WHERE region_name = 'Сибирский'),        'супермаркет');

INSERT INTO suppliers (name, inn, kpp, ogrn, legal_address, bank_name, bank_account, corr_account, bik, contact_full_name, contact_phone, contact_email) VALUES
    ('ООО «ФрешПродукт»', '7802345678', '780201001', '1137847012345',
     'Московская обл., г. Домодедово, Логистический пр-д, д. 5',
     'ПАО «СевероЗапад Банк»', '40702810500000098765', '30101810500000000765', '044030765',
     'Волков Д.С.', '+7 (911) 234-56-78', 'd.volkov@freshprodukt-demo.ru'),
    ('ООО «ЭлектроБытТех»', '7810456789', '781001001', '1147847654321',
     'г. Санкт-Петербург, Промышленный пр-т, д. 44',
     'ПАО «Кредит-Инвест Банк»', '40702810900000012345', '30101810400000000225', '044525225',
     'Григорьев С.Н.', '+7 (921) 456-78-90', 's.grigoriev@electrobyttech-demo.ru');

INSERT INTO contracts (supplier_id, contract_number, category, signed_date, valid_from, valid_to,
                       payment_delay_days, min_order_amount, volume_discount_pct, volume_discount_threshold,
                       delivery_frequency, warranty_months, penalty_late_pct, penalty_shortfall_pct, responsible_manager) VALUES
    ((SELECT supplier_id FROM suppliers WHERE name = 'ООО «ФрешПродукт»'),
     '217-ФП/2025', 'Fresh', '2025-01-15', '2025-01-15', '2026-12-31',
     21, 150000.00, 3.00, 500000.00, 'не реже 2 раз в неделю', NULL, 0.100, 0.500, 'Смирнова А.В.'),
    ((SELECT supplier_id FROM suppliers WHERE name = 'ООО «ЭлектроБытТех»'),
     '118-БТ/2026', 'Techno', '2026-02-10', '2026-03-01', '2028-02-28',
     30, 300000.00, 4.00, 1000000.00, '1 раз в 2 недели', 24, 0.100, 0.500, 'Волошина Е.И.');

INSERT INTO products (sku, name, category_code, category_name, supplier_id) VALUES
    ('FR-1001', 'Томаты грунтовые',                          'FRESH', 'Fresh', (SELECT supplier_id FROM suppliers WHERE name = 'ООО «ФрешПродукт»')),
    ('FR-1002', 'Огурцы',                                    'FRESH', 'Fresh', (SELECT supplier_id FROM suppliers WHERE name = 'ООО «ФрешПродукт»')),
    ('FR-1003', 'Зелень (петрушка/укроп)',                   'FRESH', 'Fresh', (SELECT supplier_id FROM suppliers WHERE name = 'ООО «ФрешПродукт»')),
    ('FR-1004', 'Яблоки',                                    'FRESH', 'Fresh', (SELECT supplier_id FROM suppliers WHERE name = 'ООО «ФрешПродукт»')),
    ('FR-1005', 'Бананы',                                    'FRESH', 'Fresh', (SELECT supplier_id FROM suppliers WHERE name = 'ООО «ФрешПродукт»')),
    ('FR-1006', 'Картофель молодой',                         'FRESH', 'Fresh', (SELECT supplier_id FROM suppliers WHERE name = 'ООО «ФрешПродукт»')),
    ('BBQ-1001', 'Угли древесные, 3 кг',                     'CAT-NEW-BBQ', 'Дачные товары', NULL),
    ('BBQ-1002', 'Розжиг жидкий, 0.5 л',                     'CAT-NEW-BBQ', 'Дачные товары', NULL),
    ('BBQ-1003', 'Мангал складной',                          'CAT-NEW-BBQ', 'Дачные товары', NULL),
    ('BBQ-1004', 'Маринад "Шашлычный", 300 г',                'CAT-NEW-BBQ', 'Дачные товары', NULL),
    ('BBQ-1005', 'Соус барбекю, 250 г',                       'CAT-NEW-BBQ', 'Дачные товары', NULL),
    ('BBQ-1006', 'Шампуры металлические, набор 6 шт',        'CAT-NEW-BBQ', 'Дачные товары', NULL),
    ('BBQ-1007', 'Посуда одноразовая, набор на 6 персон',    'CAT-NEW-BBQ', 'Дачные товары', NULL),
    ('BBQ-1008', 'Решётка гриль складная',                    'CAT-NEW-BBQ', 'Дачные товары', NULL),
    ('BBQ-1009', 'Специи для мяса, набор',                    'CAT-NEW-BBQ', 'Дачные товары', NULL),
    ('BBQ-1010', 'Пакеты для запекания, 10 шт',               'CAT-NEW-BBQ', 'Дачные товары', NULL);

-- Продажи по SKU за 2 квартал 2026 (сеть в целом) — источник: prodazhi-marzha-po-sku.xlsx
INSERT INTO sales_sku_monthly (sku, period, qty_sold, purchase_price, retail_price) VALUES
    ('FR-1001', '2026-04-01', 12500, 55.00, 89.00),
    ('FR-1001', '2026-05-01',  6800, 55.00, 89.00),
    ('FR-1001', '2026-06-01', 11900, 55.00, 89.00),
    ('FR-1002', '2026-04-01', 11000, 48.00, 79.00),
    ('FR-1002', '2026-05-01',  9200, 48.00, 79.00),
    ('FR-1002', '2026-06-01', 11300, 48.00, 79.00),
    ('FR-1003', '2026-04-01',  9800, 35.00, 59.00),
    ('FR-1003', '2026-05-01',  8100, 35.00, 59.00),
    ('FR-1003', '2026-06-01', 10100, 35.00, 59.00),
    ('FR-1004', '2026-04-01', 10200, 62.00, 99.00),
    ('FR-1004', '2026-05-01',  9500, 62.00, 99.00),
    ('FR-1004', '2026-06-01', 10500, 62.00, 99.00),
    ('FR-1005', '2026-04-01',  9600, 58.00, 92.00),
    ('FR-1005', '2026-05-01',  9100, 58.00, 92.00),
    ('FR-1005', '2026-06-01',  9800, 58.00, 92.00),
    ('FR-1006', '2026-04-01',  8700, 40.00, 69.00),
    ('FR-1006', '2026-05-01',  8200, 40.00, 69.00),
    ('FR-1006', '2026-06-01',  8900, 40.00, 69.00);

-- Продажи по магазинам за июнь 2026 (без разбивки по SKU) — источник: prodazhi-po-magazinam.xlsx
INSERT INTO sales_store_monthly (store_id, period, revenue, purchase_cost) VALUES
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), '2026-06-01', 18400000.00, 14330000.00),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №22'), '2026-06-01', 15200000.00, 11970000.00),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №31'), '2026-06-01', 21700000.00, 16810000.00),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №08'), '2026-06-01',  9800000.00,  7770000.00),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №19'), '2026-06-01', 11300000.00,  8930000.00),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №27'), '2026-06-01', 10600000.00,  8420000.00);

-- Остатки по акции «Дачный сезон» на начало акции (15.07.2026) — источник: ostatki-po-sku.xlsx
INSERT INTO inventory_snapshots (store_id, sku, snapshot_date, qty_on_hand, avg_daily_sales) VALUES
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), 'BBQ-1001', '2026-07-15', 180, 45),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), 'BBQ-1002', '2026-07-15',  20, 18),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), 'BBQ-1003', '2026-07-15',  12,  5),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), 'BBQ-1004', '2026-07-15',  90, 30),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), 'BBQ-1006', '2026-07-15',   8,  6),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), 'BBQ-1008', '2026-07-15',  14,  4),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №22'), 'BBQ-1001', '2026-07-15',  60, 38),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №22'), 'BBQ-1002', '2026-07-15',  55, 15),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №22'), 'BBQ-1003', '2026-07-15',   9,  4),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №22'), 'BBQ-1004', '2026-07-15',  70, 25),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №22'), 'BBQ-1006', '2026-07-15',  22,  5),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №22'), 'BBQ-1008', '2026-07-15',  18,  3),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №31'), 'BBQ-1001', '2026-07-15', 220, 50),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №31'), 'BBQ-1002', '2026-07-15',  48, 20),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №31'), 'BBQ-1003', '2026-07-15',  15,  6),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №31'), 'BBQ-1004', '2026-07-15', 110, 35),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №31'), 'BBQ-1006', '2026-07-15',  30,  7),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №31'), 'BBQ-1008', '2026-07-15',  25,  5),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №08'), 'BBQ-1001', '2026-07-15',  35, 22),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №08'), 'BBQ-1002', '2026-07-15',  12, 10),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №08'), 'BBQ-1003', '2026-07-15',   4,  3),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №08'), 'BBQ-1004', '2026-07-15',  28, 15),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №08'), 'BBQ-1006', '2026-07-15',   6,  3),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №08'), 'BBQ-1008', '2026-07-15',   5,  2),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №19'), 'BBQ-1001', '2026-07-15',  48, 20),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №19'), 'BBQ-1002', '2026-07-15',  18,  9),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №19'), 'BBQ-1003', '2026-07-15',   5,  2),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №19'), 'BBQ-1004', '2026-07-15',  33, 14),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №19'), 'BBQ-1006', '2026-07-15',  14,  4),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №19'), 'BBQ-1008', '2026-07-15',   9,  2),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №27'), 'BBQ-1001', '2026-07-15',  30, 18),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №27'), 'BBQ-1002', '2026-07-15',   9,  8),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №27'), 'BBQ-1003', '2026-07-15',   3,  2),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №27'), 'BBQ-1004', '2026-07-15',  20, 12),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №27'), 'BBQ-1006', '2026-07-15',   5,  3),
    ((SELECT store_id FROM stores WHERE store_code = 'Магазин №27'), 'BBQ-1008', '2026-07-15',   4,  2);

INSERT INTO promotions (promo_code, name, category_code, date_from, date_to, mechanics) VALUES
    ('PROMO-25-Q2-TASTE',  'Летняя дегустация',      NULL,           '2025-06-01', '2025-06-30', NULL),
    ('PROMO-25-Q3-HARVEST','Осенний урожай',         NULL,           '2025-09-01', '2025-09-30', NULL),
    ('PROMO-25-Q4-NY',     'Новогодние подарки',     NULL,           '2025-12-15', '2026-01-10', NULL),
    ('PROMO-26-Q3-DACHA',  'Дачный сезон',           'CAT-NEW-BBQ',  '2026-07-15', '2026-08-15',
     'Скидка 20% на угли/розжиг/мангалы по карте лояльности; скидка 15% на маринады/соусы/одноразовую посуду; двойные баллы при покупке от 2000 руб. по акционным SKU.');

INSERT INTO promotion_skus (promotion_id, sku, priority_rank)
SELECT (SELECT promotion_id FROM promotions WHERE promo_code = 'PROMO-26-Q3-DACHA'), sku, rank
FROM (VALUES
    ('BBQ-1001', 1), ('BBQ-1002', 2), ('BBQ-1003', 3), ('BBQ-1004', 4), ('BBQ-1005', 5),
    ('BBQ-1006', 6), ('BBQ-1007', 7), ('BBQ-1008', 8), ('BBQ-1009', 9), ('BBQ-1010', 10)
) AS t(sku, rank);

INSERT INTO promotion_effectiveness (promotion_id, revenue, avg_check, uplift_pct, loyalty_participation_pct) VALUES
    ((SELECT promotion_id FROM promotions WHERE promo_code = 'PROMO-25-Q2-TASTE'),   4200000.00,  850.00, 0.18, 0.32),
    ((SELECT promotion_id FROM promotions WHERE promo_code = 'PROMO-25-Q3-HARVEST'), 3800000.00,  720.00, 0.22, 0.28),
    ((SELECT promotion_id FROM promotions WHERE promo_code = 'PROMO-25-Q4-NY'),      9600000.00, 1950.00, 0.45, 0.51),
    ((SELECT promotion_id FROM promotions WHERE promo_code = 'PROMO-26-Q3-DACHA'),   6750000.00, 1890.00, 0.38, 0.44);

INSERT INTO customers (full_name, phone, email, loyalty_tier, card_number) VALUES
    ('Иванов Иван Иванович', '+7 (903) 111-22-33', 'i.ivanov@example-demo.ru', 'Золото', 'TL-PLUS-000481');

-- Начальный остаток баллов на 01.04.2026: 850 — фиксируем нулевой transaction для старта истории.
INSERT INTO loyalty_transactions (customer_id, store_id, receipt_number, purchase_date, purchase_amount, points_earned, points_redeemed, points_balance, note) VALUES
    ((SELECT customer_id FROM customers WHERE full_name = 'Иванов Иван Иванович'),
     (SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), 'OPENING-BALANCE', '2026-04-01', 0, 850, 0, 850, 'Начальный остаток баллов на 01.04.2026'),
    ((SELECT customer_id FROM customers WHERE full_name = 'Иванов Иван Иванович'),
     (SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), '100234', '2026-04-01', 4500.00, 225, 0, 1075, 'Обычная покупка, начислено 5% (уровень Золото)'),
    ((SELECT customer_id FROM customers WHERE full_name = 'Иванов Иван Иванович'),
     (SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), '100301', '2026-04-15', 2200.00, 0, 300, 775, 'Оплата частично баллами (списано 300)'),
    ((SELECT customer_id FROM customers WHERE full_name = 'Иванов Иван Иванович'),
     (SELECT store_id FROM stores WHERE store_code = 'Магазин №22'), '100455', '2026-05-02', 6800.00, 340, 0, 1115, NULL),
    ((SELECT customer_id FROM customers WHERE full_name = 'Иванов Иван Иванович'),
     (SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), '100522', '2026-05-20', 1500.00, 75, 0, 1190, NULL),
    ((SELECT customer_id FROM customers WHERE full_name = 'Иванов Иван Иванович'),
     (SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), '100701', '2026-06-10', 3900.00, 195, 0, 1385, NULL),
    ((SELECT customer_id FROM customers WHERE full_name = 'Иванов Иван Иванович'),
     (SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), '100987', '2026-07-12', 3200.00, 160, 0, 1545, 'Начисление зачислено 14.07.2026 (в течение 48 часов согласно правилам программы лояльности)'),
    ((SELECT customer_id FROM customers WHERE full_name = 'Иванов Иван Иванович'),
     (SELECT store_id FROM stores WHERE store_code = 'Магазин №22'), '100999', '2026-07-20', 1800.00, 90, 0, 1635, NULL);

INSERT INTO supplier_claims (supplier_id, contract_id, claim_date, claim_type, description, penalty_amount, compensation_amount, resolution) VALUES
    ((SELECT supplier_id FROM suppliers WHERE name = 'ООО «ФрешПродукт»'),
     (SELECT contract_id FROM contracts WHERE contract_number = '217-ФП/2025'),
     '2026-02-14', 'просрочка',
     'Просрочка поставки партии овощей (томаты, огурцы) для магазинов Москвы на 3 календарных дня. Причина: задержка транспорта на таможенном оформлении.',
     12400.00, NULL, 'Неустойка удержана из очередного платежа (п. 4.1 договора).'),
    ((SELECT supplier_id FROM suppliers WHERE name = 'ООО «ФрешПродукт»'),
     (SELECT contract_id FROM contracts WHERE contract_number = '217-ФП/2025'),
     '2026-03-22', 'недопоставка',
     'Недопоставка 8% объёма партии зелени (петрушка, укроп) по заказу от 18.03.2026.',
     NULL, 15600.00, 'Компенсация в виде скидки на следующую поставку; неустойка по п. 4.2 не начислялась (добровольная компенсация).'),
    ((SELECT supplier_id FROM suppliers WHERE name = 'ООО «ФрешПродукт»'),
     (SELECT contract_id FROM contracts WHERE contract_number = '217-ФП/2025'),
     '2026-05-10', 'качество',
     'Частичная порча партии томатов при транспортировке (нарушение температурного режима). Возвращено 340 кг, акт № 18 от 10.05.2026.',
     NULL, 68000.00, 'Денежная компенсация произведена в течение 5 рабочих дней (п. 3.2 договора).'),
    ((SELECT supplier_id FROM suppliers WHERE name = 'ООО «ФрешПродукт»'),
     (SELECT contract_id FROM contracts WHERE contract_number = '217-ФП/2025'),
     '2026-06-03', 'просрочка',
     'Повторная просрочка поставки на 5 календарных дней (партия для магазинов Москвы и Санкт-Петербурга). Третье нарушение сроков за 2 квартал 2026.',
     NULL, NULL, 'Категорийному менеджеру поручено подготовить материалы для пересмотра договора (п. 4.3) и направить поставщику уведомление.');

INSERT INTO employees (full_name, role, store_id, region_id, phone, email, login) VALUES
    ('Соколов П.А.',   'Директор магазина',       (SELECT store_id FROM stores WHERE store_code = 'Магазин №14'), NULL, '+7 (916) 222-11-00', 'p.sokolov@torgline-demo.ru',   'sokolov'),
    ('Дмитриева Н.В.', 'Региональный директор',   NULL, (SELECT region_id FROM regions WHERE region_name = 'Центральный'), '+7 (916) 333-22-11', 'n.dmitrieva@torgline-demo.ru', 'dmitrieva'),
    ('Егоров К.С.',    'Финансист HQ',            NULL, NULL, '+7 (916) 444-33-22', 'k.egorov@torgline-demo.ru',    'egorov'),
    ('Смирнова А.В.',  'Категорийный менеджер',   NULL, NULL, '+7 (916) 555-44-33', 'a.smirnova@torgline-demo.ru',  'smirnova'),
    ('Волошина Е.И.',  'Категорийный менеджер',   NULL, NULL, '+7 (916) 123-45-67', 'e.voloshina@torgline-demo.ru', 'voloshina'),
    ('Петрова Е.И.',   'Маркетинг-аналитик',      NULL, NULL, '+7 (916) 666-55-44', 'e.petrova@torgline-demo.ru',   'petrova');

INSERT INTO data_sensitivity_catalog (table_name, column_name, sensitivity, note) VALUES
    ('suppliers', 'inn',               'financial', 'ИНН поставщика'),
    ('suppliers', 'kpp',               'financial', 'КПП поставщика'),
    ('suppliers', 'ogrn',              'financial', 'ОГРН поставщика'),
    ('suppliers', 'legal_address',     'pii',       'Юридический адрес — потенциально идентифицирующий'),
    ('suppliers', 'bank_name',         'financial', 'Банковские реквизиты'),
    ('suppliers', 'bank_account',      'financial', 'Расчётный счёт'),
    ('suppliers', 'corr_account',      'financial', 'Корреспондентский счёт'),
    ('suppliers', 'bik',               'financial', 'БИК'),
    ('suppliers', 'contact_full_name', 'pii',       'ФИО контактного лица поставщика'),
    ('suppliers', 'contact_phone',     'pii',       'Телефон контактного лица'),
    ('suppliers', 'contact_email',     'pii',       'E-mail контактного лица'),
    ('contracts', 'warranty_months',   'contract_terms', 'Условие «Гарантийные обязательства» — маскировать всегда, по правилу из демо-сценария 9'),
    ('contracts', 'responsible_manager','pii',      'ФИО ответственного сотрудника'),
    ('sales_sku_monthly',   'purchase_price', 'financial', 'Закупочная цена — скрывается для роли «директор магазина»'),
    ('sales_store_monthly', 'purchase_cost',  'financial', 'Закупочная стоимость — скрывается для роли «директор магазина»'),
    ('sales_store_monthly', 'margin_rub',     'financial', 'Маржа — скрывается для роли «директор магазина»'),
    ('customers', 'full_name',   'pii', 'ФИО клиента'),
    ('customers', 'phone',       'pii', 'Телефон клиента'),
    ('customers', 'email',       'pii', 'E-mail клиента'),
    ('customers', 'card_number', 'pii', 'Номер карты лояльности'),
    ('employees', 'full_name',   'pii', 'ФИО сотрудника'),
    ('employees', 'phone',       'pii', 'Телефон сотрудника'),
    ('employees', 'email',       'pii', 'E-mail сотрудника');

-- =========================================================================
-- Индексы для типовых демо-запросов
-- =========================================================================

CREATE INDEX idx_sales_sku_monthly_period      ON sales_sku_monthly (period);
CREATE INDEX idx_sales_store_monthly_period    ON sales_store_monthly (period);
CREATE INDEX idx_inventory_snapshots_date      ON inventory_snapshots (snapshot_date);
CREATE INDEX idx_loyalty_transactions_customer ON loyalty_transactions (customer_id);
CREATE INDEX idx_supplier_claims_supplier      ON supplier_claims (supplier_id);
