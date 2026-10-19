-- ====================================================================
-- CREATION OF UNIFIED ANOMALY LOG (AUDIT MASTER LOG)
-- Source dataset: ecommerce-analysis-503909.raw_data.internal_inventory_raw
-- Destination dataset: ecommerce-analysis-503909.staging.internal_inventory_audit_log
-- ====================================================================

CREATE OR REPLACE TABLE `ecommerce-analysis-503909.staging.internal_inventory_audit_log` AS

WITH calculated_anomalies AS
 (SELECT sku, product_name, category, retail_price, internal_stock, reorder_point,
         -- Calculation of uniqueness flags via Window Functions
         COUNT(*) OVER(PARTITION BY sku) AS sku_dup_count,
         COUNT(*) OVER(PARTITION BY product_name) AS pname_dup_count,
    
         -- Concatenation of ALL errors of the single row
         ARRAY_TO_STRING    -- 1. INTEGRITY AND SPACES
         ([IF(TRIM(sku) != sku, 'space in SKU', NULL),
           IF(TRIM(product_name) != product_name, 'space in product_name', NULL),
           IF(TRIM(category) != category, 'space in category', NULL),
           IF(sku IS NULL, 'null SKU', NULL),
           IF(product_name IS NULL, 'null product_name', NULL),
           IF(category IS NULL, 'null category', NULL),
           IF(internal_stock IS NULL, 'null internal_stock', NULL),
           IF(retail_price IS NULL, 'null retail_price', NULL),
           IF(reorder_point IS NULL, 'null reorder_point', NULL),
           IF(LOWER(TRIM(sku)) IN ('n/a', 'na', 'null', 'none', 'unknown', '-'), 'placeholder SKU', NULL),
           IF(LOWER(TRIM(product_name)) IN ('n/a', 'na', 'null', 'none', 'unknown', '-'), 'placeholder product_name', NULL),
           IF(LOWER(TRIM(category)) IN ('n/a', 'na', 'null', 'none', 'unknown', '-'), 'placeholder category', NULL),
                           -- 2. UNIQUENESS
           IF(sku IS NOT NULL AND COUNT(*) OVER(PARTITION BY sku) > 1, 'duplicate SKU record', NULL),
      I    F(product_name IS NOT NULL AND COUNT(*) OVER(PARTITION BY product_name) > 1, 'duplicate product_name record', NULL),
      
                           -- 3. NUMERIC VALIDATION
           IF(retail_price < 0, 'negative price', NULL),
           IF(retail_price = 0, 'zero price', NULL),
           IF(internal_stock < 0, 'negative stock', NULL),
           IF(reorder_point <> 15, 'wrong reorder point', NULL),
           IF(retail_price IS NOT NULL AND retail_price != ROUND(retail_price, 2), 'unrounded decimals in price', NULL)
         ], ' | ') AS anomaly_description

  FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`)

 SELECT sku, product_name, category, retail_price, internal_stock, reorder_point, anomaly_description
  FROM calculated_anomalies
   WHERE anomaly_description IS NOT NULL 
     AND anomaly_description != ''
     ORDER BY anomaly_description;