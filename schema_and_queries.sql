-- 1. Create Dimension Customer Table
CREATE TABLE dim_customer (
    customer_id INTEGER PRIMARY KEY,
    customer_fname TEXT NOT NULL,
    customer_lname TEXT,
    customer_city TEXT NOT NULL,
    customer_country TEXT NOT NULL,
    customer_segment TEXT NOT NULL
);

-- 2. Create Dimension Product Table
CREATE TABLE dim_product (
    product_card_id INTEGER PRIMARY KEY,
    product_name TEXT NOT NULL,
    category_id INTEGER NOT NULL,
    category_name TEXT NOT NULL,
    product_price FLOAT NOT NULL
);

-- 3. Create Fact Orders Table with Foreign Keys
CREATE TABLE fact_orders (
    order_item_id INTEGER PRIMARY KEY,
    order_id INTEGER NOT NULL,
    customer_id INTEGER NOT NULL,
    product_card_id INTEGER NOT NULL,
    order_date TIMESTAMP NOT NULL,
    days_for_shipping_real INTEGER NOT NULL,
    days_for_shipment_scheduled INTEGER NOT NULL,
    sales FLOAT NOT NULL,
    order_item_quantity INTEGER NOT NULL,
    benefit_per_order FLOAT NOT NULL,
    delivery_status TEXT NOT NULL,
    late_risk INTEGER NOT NULL CHECK (late_risk IN (0, 1)),
    
    -- Constraint Definitions
    CONSTRAINT fk_fact_customer 
        FOREIGN KEY (customer_id) 
        REFERENCES dim_customer(customer_id)
        ON DELETE CASCADE,
        
    CONSTRAINT fk_fact_product 
        FOREIGN KEY (product_card_id) 
        REFERENCES dim_product(product_card_id)
        ON DELETE CASCADE
);
-- 1. Customer Segment Profitability by Country
WITH Category_Profitability AS (
    SELECT 
        c.customer_segment, 
        c.customer_country,
        SUM(f.sales) AS total_sales_revenue,
        SUM(f.benefit_per_order) AS total_profit,
        SUM(f.order_item_quantity) AS total_quantity_sold 
    FROM fact_orders f 
    JOIN dim_customer c ON f.customer_id = c.customer_id
    GROUP BY c.customer_segment, c.customer_country 
)
SELECT * 
FROM Category_Profitability
ORDER BY total_sales_revenue DESC;


-- 2. Shipping Delays Exceeding SLA by Category
WITH Shipping_Delay_by_Category AS (
    SELECT 
        p.category_name,
        AVG(f.days_for_shipping_real) AS avg_days_real, 
        AVG(f.days_for_shipment_scheduled) AS avg_days_scheduled
    FROM fact_orders f 
    JOIN dim_product p ON f.product_card_id = p.product_card_id
    GROUP BY p.category_name 
)
SELECT 
    *, 
    ROUND((avg_days_real - avg_days_scheduled)::numeric, 2) AS delay_difference 
FROM Shipping_Delay_by_Category
WHERE (avg_days_real - avg_days_scheduled) >= 1
ORDER BY delay_difference DESC;


-- 3. Top 5 Customers with Highest Late Delivery Risk & Aggregated Products
SELECT 
    c.customer_id,
    c.customer_fname || ' ' || c.customer_lname AS full_name,
    c.customer_country,
    STRING_AGG(DISTINCT p.product_name, ', ') AS late_products, 
    SUM(CASE WHEN f.late_risk = 1 THEN f.order_item_quantity ELSE 0 END) AS late_item_count,
    COUNT(CASE WHEN f.late_risk = 1 THEN 1 END) AS count_late,
    ROUND(SUM(f.sales)::numeric, 2) AS total_spend
FROM fact_orders f 
JOIN dim_customer c ON f.customer_id = c.customer_id
JOIN dim_product p ON f.product_card_id = p.product_card_id -- Fixed missing JOIN
GROUP BY c.customer_id, full_name, c.customer_country
HAVING COUNT(CASE WHEN f.late_risk = 1 THEN 1 END) > 0
ORDER BY count_late DESC
LIMIT 5;


-- 4. Top 3 Revenue-Generating Products per Category
WITH Top_3_Products_per_Category AS ( 
    SELECT 
        p.category_name, 
        p.product_name,
        SUM(f.sales) AS total_sales, 
        DENSE_RANK() OVER (
            PARTITION BY p.category_name 
            ORDER BY SUM(f.sales) DESC
        ) AS product_rank
    FROM fact_orders f 
    LEFT JOIN dim_product p ON f.product_card_id = p.product_card_id 
    GROUP BY p.category_name, p.product_name
) 
SELECT * 
FROM Top_3_Products_per_Category 
WHERE product_rank <= 3
ORDER BY category_name, product_rank;


-- 5. Monthly Revenue, Continuous Running Total & MoM Growth
WITH Monthly_Sales AS (
    SELECT 
        DATE_TRUNC('month', order_date)::date AS sales_month,
        ROUND(SUM(sales)::numeric, 2) AS total_sales
    FROM fact_orders
    GROUP BY 1
)
SELECT 
    sales_month,
    total_sales AS monthly_spend,
    -- Continuous running total (removed PARTITION BY so it snowballs across years)
    ROUND(SUM(total_sales) OVER (ORDER BY sales_month ASC)::numeric, 2) AS cumulative_running_total,
    LAG(total_sales) OVER (ORDER BY sales_month ASC) AS prev_month_spend,
    ROUND(
        (total_sales - LAG(total_sales) OVER (ORDER BY sales_month ASC)) 
        / NULLIF(LAG(total_sales) OVER (ORDER BY sales_month ASC), 0) * 100
    , 2) AS mom_growth_pct
FROM Monthly_Sales
ORDER BY sales_month ASC;


-- 6. Time Elapsed Between Subsequent Orders per Customer
WITH unique_orders AS (
    SELECT DISTINCT
        order_id,
        customer_id,
        order_date
    FROM fact_orders
),
customer_order_history AS (
    SELECT 
        order_id,
        customer_id,
        order_date,
        LAG(order_date) OVER (
            PARTITION BY customer_id 
            ORDER BY order_date
        ) AS previous_order_date,
        COUNT(order_id) OVER (
            PARTITION BY customer_id
        ) AS total_customer_orders
    FROM unique_orders
)
SELECT 
    order_id,
    customer_id,
    order_date,
    (order_date::date - previous_order_date::date) AS days_since_previous_order
FROM customer_order_history
WHERE total_customer_orders > 1
ORDER BY customer_id, order_date;


-- 7. High-Value Cross-Category Customers (Cross-Selling Analytics)
SELECT 
    c.customer_id,
    c.customer_fname || ' ' || c.customer_lname AS full_name,
    ROUND(SUM(f.sales)::numeric, 2) AS total_lifetime_spend,
    COUNT(DISTINCT f.order_id) AS total_distinct_orders,
    COUNT(DISTINCT p.category_name) AS total_distinct_categories
FROM fact_orders f 
JOIN dim_customer c ON f.customer_id = c.customer_id 
JOIN dim_product p ON f.product_card_id = p.product_card_id
GROUP BY c.customer_id, full_name
HAVING COUNT(DISTINCT p.category_name) >= 4
ORDER BY total_lifetime_spend DESC;


-- 8. Average Days to Second Purchase by Customer Segment (Activation SLA)
WITH Distinct_Orders AS (
    SELECT DISTINCT
        c.customer_id,
        c.customer_segment,
        f.order_id,
        f.order_date
    FROM fact_orders f
    JOIN dim_customer c ON f.customer_id = c.customer_id
),
ranked_orders AS (
    SELECT 
        customer_id,
        customer_segment,
        order_date, 
        LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS previous_order_date, 
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date ASC) AS order_num 
    FROM Distinct_Orders  
)
SELECT 
    customer_segment, 
    ROUND(AVG(order_date::date - previous_order_date::date), 2) AS avg_days_between_1st_and_2nd_purchase 
FROM ranked_orders 
WHERE order_num = 2 
GROUP BY customer_segment;


-- 9. Negative Margin Analysis for High-Value Orders (Leakage Identification)
SELECT 
    f.order_id,
    c.customer_fname || ' ' || c.customer_lname AS customer_full_name,
    SUM(f.sales) AS total_sales,
    SUM(f.benefit_per_order) AS total_profit,
    ROUND((SUM(f.benefit_per_order) * 100.0 / NULLIF(SUM(f.sales), 0))::numeric, 2) AS profit_margin_pct
FROM fact_orders f
JOIN dim_customer c ON f.customer_id = c.customer_id
GROUP BY f.order_id, c.customer_fname, c.customer_lname
HAVING SUM(f.sales) > 500 
   AND SUM(f.benefit_per_order) < 0
ORDER BY total_profit ASC;
