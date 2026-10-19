-- ====================================================================
-- DATA AUDITING ON: supplier_feed_raw
-- Identifying anomalies before the cleaning phase
-- ===================================================================
-- PHASE 1: SINGLE-SOURCE DATA QUALITY AUDIT
-- ===================================================================

 -- 1. INTEGRITY AND FORMAT: Full SKU Key Validation --

 -- NOTE:   We check for null/blank SKUs, dirty placeholders, leading/trailing spaces
 --         and internal spaces to ensure the SKU key is properly formatted before pattern validation.
 --         We use ARRAY_TO_STRING combined with QUALIFY to dynamically display error types

 -- RESULT: no errors found, SKU key integrity is fully preserved

  SELECT sku,
         ARRAY_TO_STRING
         ([IF(sku IS NULL OR TRIM(sku) = '', 'null or blank SKU', NULL),
           IF(LOWER(TRIM(sku)) IN ('n/a', 'na', 'null', 'none', 'unknown', '-'), 'placeholder in SKU', NULL),
           IF(TRIM(sku) != sku, 'trailing/leading space in SKU', NULL),
           IF(REGEXP_CONTAINS(sku, r'\S\s+\S'), 'internal space in SKU', NULL)
          ], ' | ') AS sku_errors
   FROM `ecommerce-analysis-503909.raw_data.supplier_feed_raw`
    QUALIFY LENGTH(sku_errors) > 0
      ORDER BY sku_errors;



 -- 2. SKU COMPLIANCE CHECK: Checking SKU regex pattern (SKU-XXXX) --

 -- NOTE:   We use a CTE, a sequential CASE WHEN and the case-insensitive flag `(?i)` to  
 --         differentiate between structural format errors and simple casing mismatches

 -- RESULT: 10 casing mismatches in SKU and 0 structural format errors

  WITH sku_checks AS
   (SELECT sku,
           CASE WHEN NOT REGEXP_CONTAINS(TRIM(sku), r'(?i)^sku-\d{4}$') THEN 'structural format error' -- Verifies the SKU structure (case-insensitive)
                WHEN NOT REGEXP_CONTAINS(TRIM(sku), r'^SKU-\d{4}$') THEN 'casing mismatch in SKU' -- Verifies the SKU casing (case-sensitive)
           END AS error_type
     FROM `ecommerce-analysis-503909.raw_data.supplier_feed_raw`
      WHERE sku IS NOT NULL)

  SELECT *
    FROM sku_checks
     WHERE error_type IS NOT NULL;



 -- 3. CONFLICTING SKU DATA: Duplicate rows and potential price/stock differences --

 -- NOTE:   We use the QUALIFY clause to filter window function results directly,
 --         identifying duplicate SKUs (even with casing or space differences)
 --         without needing nested subqueries or CTEs 

 -- RESULT: no errors

  SELECT sku, supplier_stock, wholesale_cost
   FROM `ecommerce-analysis-503909.raw_data.supplier_feed_raw`
     WHERE sku IS NOT NULL
      QUALIFY COUNT(*) OVER(PARTITION BY UPPER(TRIM(sku))) > 1
       ORDER BY UPPER(TRIM(sku));



 -- 4. WRONG NUMBER VALUES: Validate numerical precision of wholesale_cost and supplier_stock --

 -- NOTE:   we use ARRAY_TO_STRING to capture all numeric anomalies in a single scan,
 --         FLOOR() checks for integer stock compliance without type casting, 
 --         while QUALIFY eliminates the need for a redundant WHERE clause

 -- RESULT: no errors, all costs are positive and stock counts are valid non-negative integers

  SELECT sku, supplier_stock, wholesale_cost,
         ARRAY_TO_STRING
         ([IF(wholesale_cost IS NULL, 'null cost', NULL),
           IF(wholesale_cost < 0, 'negative cost', NULL),
           IF(wholesale_cost = 0, 'zero cost', NULL),
           IF(supplier_stock IS NULL, 'null stock', NULL),
           IF(supplier_stock < 0, 'negative stock', NULL),
           IF(supplier_stock != FLOOR(supplier_stock), 'non-integer stock', NULL)
          ], ' | ') AS numeric_anomalies
   FROM `ecommerce-analysis-503909.raw_data.supplier_feed_raw`
    QUALIFY LENGTH(numeric_anomalies) > 0
     ORDER BY numeric_anomalies;




 -- 5. NUMERIC COMPLIANCE CHECK: Wholesale costs with unrounded decimals --

 -- NOTE:   we intentionally split numeric validation into two distinct queries to separate concerns
 --         by severity level, decimals beyond 2 places don't block operations but equire cleanup.
 --         We calculate exact decimal_difference using ABS()

 -- RESULT: no errors

  SELECT sku, supplier_stock, wholesale_cost,
         ROUND(wholesale_cost, 2) AS wholesale_cost_rounded,
         ABS(wholesale_cost - ROUND(wholesale_cost, 2)) AS decimal_difference
   FROM `ecommerce-analysis-503909.raw_data.supplier_feed_raw`
    WHERE wholesale_cost IS NOT NULL
      AND ABS(wholesale_cost - ROUND(wholesale_cost, 2)) > 0.00001
      ORDER BY decimal_difference DESC;



-- ===================================================================
-- PHASE 2: CROSS-SYSTEM INTEGRITY & MATCHING w/internal_inventory
-- ===================================================================

 -- 1: MATCH ISSUES: SKU Matching and referential integrity (case-insensitive) --

 -- NOTE:   We use UNION ALL + GROUP BY + COUNTIF instead of a FULL OUTER JOINl,
 --         allowing COUNTIF to efficiently aggregate and flag referential 
 --         integrity issues in a single, highly optimized pass

 -- RESULT: 8 total match issues
 --         3 duplicate SKU (internal)
 --         5 SKUs in supplier NOT in internal (SKU-9991...9995)

  WITH combined_sources AS
   (SELECT UPPER(TRIM(sku)) AS consolidated_sku, 'internal' AS source 
     FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw` 
      WHERE sku IS NOT NULL AND TRIM(sku) != ''

    UNION ALL

    SELECT UPPER(TRIM(sku)) AS consolidated_sku, 'supplier' AS source 
     FROM `ecommerce-analysis-503909.raw_data.supplier_feed_raw` 
      WHERE sku IS NOT NULL AND TRIM(sku) != '' ),

  aggregated_matches AS
   (SELECT consolidated_sku,
           COUNTIF(source = 'internal') AS internal_count,
           COUNTIF(source = 'supplier') AS supplier_count
     FROM combined_sources
      GROUP BY consolidated_sku)

  SELECT consolidated_sku, internal_count, supplier_count,
         ARRAY_TO_STRING
         ([IF(internal_count = 0, 'SKU in supplier NOT in internal', NULL),
           IF(supplier_count = 0, 'SKU in internal NOT in supplier', NULL),
           IF(internal_count > 1, 'duplicate in internal', NULL),
           IF(supplier_count > 1, 'duplicate in supplier', NULL)
          ], ' | ') AS match_issue_type
   FROM aggregated_matches
    WHERE internal_count = 0 
       OR supplier_count = 0 
       OR internal_count > 1 
       OR supplier_count > 1
       ORDER BY match_issue_type, consolidated_sku;

 -- --------------------------------------------------------------------
 -- 2. DRILL-DOWN INSPECTION: Quick inspection of orphan supplier records
 -- --------------------------------------------------------------------

 -- NOTE:   Targeted query to inspect the specific orphan records (SKU-999x)
 --         identified during cross-system validation.

  SELECT sku, supplier_stock, wholesale_cost
   FROM `ecommerce-analysis-503909.raw_data.supplier_feed_raw`
    WHERE UPPER(TRIM(sku)) LIKE 'SKU-999%';