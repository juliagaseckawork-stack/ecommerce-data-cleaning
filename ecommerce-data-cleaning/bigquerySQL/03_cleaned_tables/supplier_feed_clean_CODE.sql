-- ====================================================================
-- STAGING LAYER CREATION: supplier_feed_cleaned
-- Objective: Minimalist & Surgical Cleansing with Cross-System Audit Flags
-- Structure: Fully aligned with internal_inventory_cleaned methodology
-- ====================================================================

CREATE OR REPLACE TABLE `ecommerce-analysis-503909.staging.supplier_feed_cleaned` AS

 WITH targeted_cleansing AS
  (SELECT UPPER(sku) AS clean_sku,                                   -- 1. SKU fixing casing mismatch only
          supplier_stock AS clean_supplier_stock,                    -- 2. SUPPLIER STOCK
          wholesale_cost AS clean_wholesale_cost                     -- 3. WHOLESALE COST
   FROM `ecommerce-analysis-503909.raw_data.supplier_feed_raw`
    WHERE sku IS NOT NULL AND TRIM(sku) != ''),

 cross_system_audit AS
  (SELECT tc.*,
          IF(int.sku IS NULL, TRUE, FALSE) AS is_orphan_supplier_sku -- Check if SKU exists in the cleaned internal inventory dataset
    FROM targeted_cleansing tc
     LEFT JOIN `ecommerce-analysis-503909.staging.internal_inventory_cleaned` int
     ON tc.clean_sku = int.sku)
 
 SELECT clean_sku AS sku, 
        clean_supplier_stock AS supplier_stock, 
        clean_wholesale_cost AS wholesale_cost, 

        -- AUDIT NOTES FOR EXCEL (uses ARRAY_TO_STRING to return '' instead of NULL for clean records)
        ARRAY_TO_STRING
        ([IF(is_orphan_supplier_sku, 'SKU in supplier NOT in internal inventory', NULL)
         ], ' | ') AS audit_notes,

        -- EXCEL ACTIONABLE FLAG (triggers TRUE for orphan records requiring business review)
        IF(is_orphan_supplier_sku, TRUE, FALSE) AS requires_manual_review

  FROM cross_system_audit
   ORDER BY requires_manual_review DESC, audit_notes ASC, sku ASC;