-- ====================================================================
-- CREATION OF UNIFIED SUPPLIER ANOMALY LOG (AUDIT MASTER LOG)
-- Source dataset: ecommerce-analysis-503909.raw_data.supplier_feed_raw
-- Destination dataset: ecommerce-analysis-503909.staging.supplier_feed_audit_log
-- ====================================================================

CREATE OR REPLACE TABLE `ecommerce-analysis-503909.staging.supplier_feed_audit_log` AS

WITH calculated_anomalies AS
 (SELECT s.sku, s.wholesale_cost,s.supplier_stock,
    
    -- Concatenation of ALL errors present on the single row
    ARRAY_TO_STRING       -- 1. SKU INTEGRITY AND FORMAT
    ([IF(s.sku IS NULL OR TRIM(s.sku) = '', 'null or blank SKU', NULL),
      IF(LOWER(TRIM(s.sku)) IN ('n/a', 'na', 'null', 'none', 'unknown', '-'), 'placeholder SKU', NULL),
      IF(TRIM(s.sku) != s.sku, 'outer spaces in SKU', NULL),
      IF(REGEXP_CONTAINS(s.sku, r'\s+'), 'internal spaces in SKU', NULL),
      IF(REGEXP_CONTAINS(s.sku, r'(?i)^sku-\d{4}$') AND NOT REGEXP_CONTAINS(s.sku, r'^SKU-\d{4}$'), 'casing mismatch in SKU', NULL),
      
                          -- 2. NUMERIC VALIDATION
      IF(s.wholesale_cost IS NULL, 'null cost', NULL),
      IF(s.supplier_stock IS NULL, 'null stock', NULL),
      IF(s.wholesale_cost <= 0, 'wrong cost (<=0)', NULL),
      IF(s.supplier_stock < 0, 'wrong stock (<0)', NULL),
      IF(s.wholesale_cost IS NOT NULL AND s.wholesale_cost != ROUND(s.wholesale_cost, 2), '>2 decimals in cost', NULL),
      IF(s.supplier_stock IS NOT NULL AND s.supplier_stock != FLOOR(s.supplier_stock), 'stock not integer', NULL),
      IF(s.supplier_stock > 0 AND (s.wholesale_cost IS NULL OR s.wholesale_cost <= 0), 'stock present with invalid cost', NULL),
      
                          -- 3. CROSS-SYSTEM INTEGRITY (Directly integrated via LEFT JOIN)
      IF(s.sku IS NOT NULL AND i.sku IS NULL, 'SKU in supplier NOT in internal inventory', NULL)
     ], ' | ') AS anomaly_description

  FROM `ecommerce-analysis-503909.raw_data.supplier_feed_raw` s
  LEFT JOIN `ecommerce-analysis-503909.raw_data.internal_inventory_raw` i
         ON UPPER(TRIM(s.sku)) = UPPER(TRIM(i.sku)))

 SELECT sku, wholesale_cost, supplier_stock, anomaly_description
  FROM calculated_anomalies
   WHERE anomaly_description IS NOT NULL 
     AND anomaly_description != ''
     ORDER BY anomaly_description, sku;