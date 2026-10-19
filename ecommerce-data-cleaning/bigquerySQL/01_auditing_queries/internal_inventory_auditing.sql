-- ====================================================================
-- DATA AUDITING ON: internal_inventory_raw
-- Identify anomalies before the cleaning phase
-- ====================================================================

-- ====================================================================
-- PHASE 1: BASIC STRING ERRORS
-- ====================================================================

 -- 1. TRAILING & INTERNAL SPACE ERRORS --

 -- NOTE:   We use ARRAY_TO_STRING combined with IF conditions to flag multiple space-related anomalies per row,
 --         this approach avoids multiple queries or complex nested CASE statements, 
 --         we create an array of error flags for each row and concatenate them 
 --         into a single readable string

 -- RESULT: 8 rows with trailing/leading space in SKU

  WITH flagged_errors AS

  (SELECT sku, product_name, category,
          ARRAY_TO_STRING
         ([IF(TRIM(sku) != sku, 'trailing/leading space in SKU', NULL),
           IF(REGEXP_CONTAINS(sku, r'\S\s+\S'), 'internal spaces in SKU', NULL), -- Look for random internal spaces within the SKU
           IF(TRIM(product_name) != product_name, 'trailing/leading space in product', NULL), 
           IF(REGEXP_CONTAINS(product_name, r'\S\s+\S'), 'internal spaces in product', NULL), -- Look for multiple spaces within the product name
           IF(TRIM(category) != category, 'trailing/leading space in category', NULL), 
           IF(REGEXP_CONTAINS(category, r'\S\s+\S'), 'internal spaces in category', NULL) -- Look for random internal spaces within the category
          ], ' | ') AS spaces
      FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`)
  
  SELECT *
   FROM flagged_errors
    WHERE spaces != ''
     ORDER BY spaces;



 -- 2. INTEGRITY CHECK: Searching for NULL fields --

 -- NOTE:   We check all columns to ensure no critical data is missing at the row level
 --         using COUNTIF instead of ARRAY_TO_STRING (no need to concatenate error flags)

 -- RESULT: 10 total NULL values (5 in category, 5 in reorder_point)

  SELECT COUNTIF(sku IS NULL) AS null_sku,
         COUNTIF(product_name IS NULL) AS null_product_name,
         COUNTIF(category IS NULL) AS null_category,
         COUNTIF(internal_stock IS NULL) AS null_internal_stock,
         COUNTIF(retail_price IS NULL) AS null_retail_price,
         COUNTIF(reorder_point IS NULL) AS null_reorder_point
   FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`;



 -- 3. PLACEHOLDER VALUES: Missing values flagged differently in strings --

 -- NOTE:   We use LOWER(TRIM()) to make the check case-insensitive 
 --         and immune to accidental trailing spaces and more readeble then REGEXP.
 --         This catches "dirty" nulls like 'N/A' or 'null' that bypass standard IS NULL checks.

 -- RESULT: no errors

  WITH flagged_placeholders AS

   (SELECT sku, product_name, category,
           ARRAY_TO_STRING
           ([IF(LOWER(TRIM(sku)) IN ('', 'n/a', 'na', 'null', 'none', 'unknown', '-'), 'placeholder in SKU', NULL),
             IF(LOWER(TRIM(product_name)) IN ('', 'n/a', 'na', 'null', 'none', 'unknown', '-'), 'placeholder in product_name', NULL),
             IF(LOWER(TRIM(category)) IN ('', 'n/a', 'na', 'null', 'none', 'unknown', '-'), 'placeholder in category', NULL)
            ], ' | ') AS placeholder_errors
      FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`)

  SELECT *
   FROM flagged_placeholders
    WHERE placeholder_errors != '';


-- ====================================================================
-- PHASE 2: FORMAT AND IDENTIFIER COMPLIANCE
-- ====================================================================

 -- 1. SKU COMPLIANCE CHECK: Checking SKU regex pattern (SKU-XXXX) --

 -- NOTE:   REGEXP_CONTAINS is optimized in BQ for string matching ,
 --         We use the case-insensitive flag `(?i)` to differentiate 
 --         between structural format errors and simple casing mismatches and TRIM
 --         to avoid false positives due to leading/trailing spaces.

 -- RESULT: no errors

  WITH sku_checks AS

   (SELECT sku,
           CASE  WHEN NOT REGEXP_CONTAINS(TRIM(sku), r'(?i)^sku-\d{4}$') THEN 'structural format error' -- Verifies the SKU structure (case-insensitive)
                 WHEN NOT REGEXP_CONTAINS(TRIM(sku), r'^SKU-\d{4}$') THEN 'casing mismatch in SKU' -- Verifies the SKU casing (case-sensitive)
           END AS error_type
     FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`
      WHERE sku IS NOT NULL)

  SELECT *
   FROM sku_checks
    WHERE error_type IS NOT NULL;



 -- 2. PRODUCT COMPLIANCE CHECK: Searching for suspicious symbols and multiple spaces --

 -- NOTE:   We use a whitelist regular expression  with r"..." to allow single
 --         quotes ' within the pattern without break-escaping issues.
 --         This catches any unexpected symbol, special character, or double space 
 --         not explicitly permitted in standard product names.

 -- RESULT: no errors

  SELECT product_name
   FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`
    WHERE product_name IS NOT NULL
      AND REGEXP_CONTAINS(product_name, r"[^a-zA-Z0-9\s-(),.'///]");



 -- 3. UNIQUENESS CHECK: Search for duplicate SKUs --

 -- NOTE:   We use the QUALIFY clause instead of filtering by a window function
 --         that requires wrapping the query in a subquery,
 --         BigQuery's QUALIFY allows us to filter window function results directly

 -- RESULT: 3 duplicate SKUs with duplicate product names with conflicting data on retail_price and category
 --         SKU-1015 = retail_price 33.58 / 91.71
 --         SKU-1108 = category Sports / Toys
 --         SKU-1301 = retail_price 8.66 / 15.96

  SELECT sku, product_name, category, internal_stock, retail_price, reorder_point
   FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`
     WHERE sku IS NOT NULL
       QUALIFY COUNT(*) OVER(PARTITION BY UPPER(TRIM(sku))) > 1
       ORDER BY sku;



 -- 4. UNIQUENESS CHECK: Searching for duplicate product_names --

 -- NOTE:   Same use of QUALIFY for clean window function filtering.

 -- RESULT: 11 duplicate product_names (22 total rows)
 --         3 with same SKU (due to duplicate SKU)
 --         8 all with conflicting data simultaneously in SKU, internal_stock, retail_price
 --         out of 11 duplicates, only 1 has conflicting category (due to duplicate SKU)

  SELECT sku, product_name, category, internal_stock, retail_price, reorder_point
   FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`
     WHERE product_name IS NOT NULL
       QUALIFY COUNT(*) OVER(PARTITION BY UPPER(TRIM(product_name))) > 1
       ORDER BY product_name;



 -- 5. INCORRECT CASING: Casing inconsistencies in category --

 -- NOTE:   By grouping by LOWER(category) and counting DISTINCT original categories, 
 --         we instantly check if "Sports" and "sports" both exist,
 --         STRING_AGG is a BQ specific function that concatenates values into a single string

 -- RESULT: no errors

  SELECT LOWER(TRIM(category)) AS category_base,
         COUNT(DISTINCT TRIM(category)) AS variant_count,
         STRING_AGG(DISTINCT TRIM(category), ', ') AS variants_found
   FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`
     WHERE category IS NOT NULL
      GROUP BY LOWER(TRIM(category))
        HAVING COUNT(DISTINCT TRIM(category)) > 1;



 -- 6. ANOMALOUS PRODUCT LENGTH: Searching for names that are too short or very long --

 -- NOTE:   We rank product name lengths using Window Functions,
 --         then extract the top 5 shortest and top 5 longest names to inspect 
 --         boundary values for data quality issues using CASE WHEN

 -- RESULT: no anomalies regarding product_name length were detected during the manual check.

  WITH ranked_lengths AS

   (SELECT product_name,
           LENGTH(TRIM(product_name)) AS name_length,
           ROW_NUMBER() OVER(ORDER BY LENGTH(TRIM(product_name)) ASC) AS rank_shortest, -- From shortest to longest
           ROW_NUMBER() OVER(ORDER BY LENGTH(TRIM(product_name)) DESC) AS rank_longest  -- From longest to shortest
     FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`
      WHERE product_name IS NOT NULL)

  SELECT product_name, name_length,
         CASE WHEN rank_shortest <= 5 THEN 'top 5 shortest'
              ELSE 'top 5 longest'
         END AS boundary_category
   FROM ranked_lengths
    WHERE rank_shortest <= 5 
       OR rank_longest <= 5
       ORDER BY name_length ASC;


-- ====================================================================
-- PHASE 3: NUMERIC VALIDATION
-- ====================================================================

 -- 1. PRICES AND STOCK: Searching for invalid prices, stock levels, and reorder points --

 -- NOTE:   We use ARRAY_TO_STRING with IF conditions to flag multiple co-occurring 
 --         numeric anomalies per row, QUALIFY LENGTH(anomaly_types) > 0 filters
 --         just the rows where the error string is not empty,
 --         FLOOR() verifies that stock and reorder point fields contain integer values.

 -- RESULT: 8 total anomalies, only in retail_price column (4 'negative price', 4 'zero price')

  SELECT sku, product_name, retail_price, internal_stock, reorder_point,
         ARRAY_TO_STRING
         ([IF(retail_price < 0, 'negative price', NULL),
           IF(retail_price = 0, 'zero price', NULL),
           IF(internal_stock < 0, 'negative stock', NULL),
           IF(internal_stock != FLOOR(internal_stock), 'stock not integer', NULL),
           IF(reorder_point IS NOT NULL AND reorder_point != 15, 'wrong reorder point', NULL),
           IF(reorder_point != FLOOR(reorder_point), 'reorder point not integer', NULL)
          ], ' | ') AS anomaly_types
   FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`
    QUALIFY LENGTH(anomaly_types) > 0
     ORDER BY anomaly_types;



 -- 2. EXTREME PRICES BY CATEGORY: Searching for min and max values for products --

 -- NOTE:   Instead of using ROW_NUMBER() or self-joins we use ARRAY_AGG with an ORDER BY and LIMIT 1,
 --         then extract the first element using [OFFSET(0)], improving code readability

 -- RESULT: no anomalies in extreme prices

  SELECT category,
         MIN(retail_price) AS min_price,
         ARRAY_AGG(product_name ORDER BY retail_price ASC, product_name ASC LIMIT 1)[OFFSET(0)] AS cheapest_product,
         MAX(retail_price) AS max_price,
         ARRAY_AGG(product_name ORDER BY retail_price DESC, product_name ASC LIMIT 1)[OFFSET(0)] AS most_expensive_product
   FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`
    WHERE retail_price > 0 
      AND category IS NOT NULL
      GROUP BY category
      ORDER BY category;



 -- 3. NUMERIC COMPLIANCE CHECK: Prices with unrounded decimals --

 -- NOTE:   We calculate the absolute difference between the raw price and its 
 --         2-decimal rounded version. A threshold check (ABS > 0.00001) avoids 
 --         false positives caused by floating-point representation issues.

 -- RESULT: No errors

  SELECT sku, product_name, retail_price,
         ROUND(retail_price, 2) AS retail_price_rounded,
         ABS(retail_price - ROUND(retail_price, 2)) AS decimal_difference
   FROM `ecommerce-analysis-503909.raw_data.internal_inventory_raw`
    WHERE retail_price IS NOT NULL
      AND ABS(retail_price - ROUND(retail_price, 2)) > 0.00001
      ORDER BY decimal_difference DESC;