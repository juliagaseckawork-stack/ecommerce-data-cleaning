-- ====================================================================
-- STAGING LAYER CREATION: internal_inventory_cleaned
-- Objective: Minimalist & Surgical Cleansing based strictly on Audit Log findings
-- ====================================================================

CREATE OR REPLACE TABLE `ecommerce-analysis-503909.staging.internal_inventory_cleaned` AS

WITH targeted_cleansing AS
  (SELECT UPPER(TRIM(sku)) AS clean_sku,                                   -- 1. SKU fixing trailing/leading spaces only
          product_name AS clean_product_name,                              -- 2. PRODUCT NAME
          CASE 
            WHEN category IS NULL OR TRIM(category) = '' THEN 'Unknown'    -- 3. CATEGORY changing NULLs to Unassigned
            ELSE category
          END AS clean_category,  
          IF(retail_price > 0, retail_price, NULL) AS clean_retail_price,  -- 4. RETAIL PRICE set zero/negative prices to NULL
          internal_stock AS clean_internal_stock,                          -- 5. INTERNAL STOCK
          COALESCE(reorder_point, 15) AS clean_reorder_point               -- 6. REORDER POINT set NULLs to standard business default (15)

   FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`
   WHERE sku IS NOT NULL AND TRIM(sku) != ''),

audit_and_dedupe AS
  (SELECT clean_sku, clean_product_name, clean_category, clean_retail_price, clean_internal_stock, clean_reorder_point,
          -- Count occurrences for exact flag identification
          COUNT(*) OVER(PARTITION BY clean_sku) AS sku_occurrence_count,
          COUNT(*) OVER(PARTITION BY clean_product_name) AS product_name_occurrence_count,

          -- Detect attribute conflicts across duplicate SKUs
          COUNT(DISTINCT clean_retail_price) OVER(PARTITION BY clean_sku) > 1 AS price_conflict_flag,
          COUNT(DISTINCT clean_category) OVER(PARTITION BY clean_sku) > 1 AS category_conflict_flag,

          -- DEDUPLICATION RULE: Guaranteed 1 row per SKU for primary key integrity
          ROW_NUMBER() OVER
          (PARTITION BY clean_sku ORDER BY
                     IF(clean_retail_price IS NOT NULL, 1, 0) DESC, -- Priority 1: Valid price
                     IF(clean_category != 'Unknown', 1, 0) DESC,    -- Priority 2: Valid category
                     clean_internal_stock DESC                      -- Priority 3: Highest stock
          ) AS row_num
  FROM targeted_cleansing)

SELECT clean_sku AS sku,
       clean_product_name AS product_name,
       clean_category AS category,
       clean_retail_price AS retail_price,
       clean_internal_stock AS internal_stock,
       clean_reorder_point AS reorder_point,

       -- AUDIT NOTES FOR EXCEL
       ARRAY_TO_STRING
       ([IF(sku_occurrence_count > 1, 'Duplicate SKU resolved', NULL),
         IF(product_name_occurrence_count > 1, 'Shared product name across SKUs', NULL),
         IF(price_conflict_flag, 'Conflicting prices for SKU', NULL),
         IF(category_conflict_flag, 'Conflicting categories for SKU', NULL),
         IF(clean_retail_price IS NULL, 'Invalid price (<=0)', NULL),
         IF(clean_category = 'Unknown', 'Missing or corrupted category', NULL)
        ], ' | ') AS audit_notes,

       -- EXCEL ACTIONABLE FLAG
         IF(sku_occurrence_count > 1 
            OR product_name_occurrence_count > 1
            OR price_conflict_flag 
            OR category_conflict_flag 
            OR clean_retail_price IS NULL 
            OR clean_category = 'Unknown', TRUE, FALSE
           ) AS requires_manual_review

FROM audit_and_dedupe
WHERE row_num = 1
ORDER BY requires_manual_review DESC, audit_notes ASC, product_name ASC;
