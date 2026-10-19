-- ====================================================================
-- DATA MART: inventory_supplier_consolidated
-- Unified operational, financial & supply chain intelligence
-- ====================================================================

CREATE OR REPLACE TABLE `ecommerce-analysis-503909.data_mart.inventory_supplier_consolidated` AS

SELECT -- 1. CONSOLIDATED IDENTIFIERS
       COALESCE(i.sku, s.sku) AS consolidated_sku,
       i.product_name,
       i.category,
        
       -- 2. INTEGRATION STATUS 
       CASE WHEN i.sku IS NOT NULL AND s.sku IS NOT NULL THEN 'MATCHED'
            WHEN i.sku IS NOT NULL AND s.sku IS NULL THEN 'INTERNAL ONLY'
            WHEN i.sku IS NULL AND s.sku IS NOT NULL THEN 'SUPPLIER ONLY'
       END AS catalog_integration_status,
        
       -- 3. FINANCIAL & MARGIN ANALYSIS
       i.retail_price,
       s.wholesale_cost AS current_supplier_cost,
       ROUND(i.retail_price - s.wholesale_cost, 2) AS current_unit_margin_amount, -- Unit margin amount  
       ROUND(SAFE_DIVIDE(i.retail_price - s.wholesale_cost, i.retail_price) * 100, 2) AS current_margin_percentage, -- Unit margin percentage (%)
       CASE WHEN i.retail_price IS NOT NULL AND s.wholesale_cost IS NOT NULL AND (i.retail_price - s.wholesale_cost) < 0 
            THEN 'CRITICAL Negative margin'
            WHEN SAFE_DIVIDE(i.retail_price - s.wholesale_cost, i.retail_price) < 0.20 
            THEN 'WARNING Low margin <20%'
            WHEN i.retail_price IS NOT NULL AND s.wholesale_cost IS NOT NULL 
            THEN 'MARGIN OK' 
       ELSE 'N/A Missing price data'
       END AS margin_health_status, -- Margin health alert
        
       -- 4. AVAILABILITY DYNAMICS
       COALESCE(i.internal_stock, 0) AS internal_stock,
       i.reorder_point,
       COALESCE(s.supplier_stock, 0) AS supplier_stock,
       COALESCE(i.internal_stock, 0) + COALESCE(s.supplier_stock, 0) AS total_system_availability,
        
       -- Reorder & Stockout Alerts
       CASE WHEN COALESCE(i.internal_stock, 0) = 0 AND COALESCE(s.supplier_stock, 0) > 0 
            THEN 'CRITICAL Internal stockout - reorder available from Supplier' 
            WHEN COALESCE(i.internal_stock, 0) = 0 AND COALESCE(s.supplier_stock, 0) = 0 
            THEN 'OUT OF STOCK from Internal & Supplier'
            WHEN i.reorder_point IS NOT NULL AND COALESCE(i.internal_stock, 0) <= i.reorder_point AND COALESCE(s.supplier_stock, 0) > 0
            THEN 'WARNING Below reorder point - reorder available from Supplier'
            WHEN COALESCE(i.internal_stock, 0) > 0 
            THEN 'HEALTHY AVAILABILITY Internal available stock'
       ELSE 'SUPPLIER ONLY Not mapped in Internal'
       END AS stock_health_status,
        
       -- 5. SUPPLY CHAIN ROUTING
       CASE WHEN COALESCE(i.internal_stock, 0) > 0 
            THEN 'Fulfill in-house' 
            WHEN COALESCE(i.internal_stock, 0) = 0 AND COALESCE(s.supplier_stock, 0) > 0 
            THEN 'Fulfill via dropship'
       ELSE 'Out of stock'
       END AS recommended_fulfillment_route
        
FROM `ecommerce-analysis-503909.staging.internal_inventory_cleaned` i
 FULL OUTER JOIN `ecommerce-analysis-503909.staging.supplier_feed_cleaned` s
  ON i.sku = s.sku
  ORDER BY catalog_integration_status DESC, consolidated_sku ASC;