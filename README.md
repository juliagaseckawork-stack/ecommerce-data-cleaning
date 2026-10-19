# ecommerce-data-cleaning: E-Commerce Inventory & Suppliers

Data Cleaning & Auditing project focused on managing inventory and supplier master data for an e-commerce business. Using SQL scripts in BigQuery, anomalies and duplicates were identified and corrected, generating standardized datasets and final reports for monitoring warehouse performance.

## Repository Structure

The project is organized into the following folders:

*   `bigqueryData/`: Contains the `.csv` files exported directly from BigQuery, capturing the state of the tables (inventory and supplier).
*   `bigquerySQL/`: Contains all the SQL scripts used for data auditing activities and table creation.
*   `excel/`: Includes the operational analysis Excel file developed based on the Data Mart table processed in BigQuery.
*   `reports/`: Contains the final summary reports, both related to the SQL analyses and the Excel file.

## Section Details

**bigqueryData:**
This folder contains the raw data and the tables created on BigQuery.
*   Format: `.csv`
*   Datasets: `01_raw_data`, `02_staging`, `03_data_mart`

**bigquerySQL:**
The SQL queries used throughout the project are saved here. The queries are divided by purpose:
*   **Auditing:** Queries written to identify anomalies, duplicates, null values, or inconsistencies in the Inventory and Supplier data.
*   **Audit Log Creation:** DDL queries used to generate tables that flag all errors detected during the auditing phase.
*   **Cleaning:** DDL/DML queries to create cleaned tables without affecting the original Raw tables.
*   **Consolidation:** JOIN queries between Inventory and Supplier to create a single Data Mart table with all the necessary data to detect further operational discrepancies.

**excel:**
The file inside takes inspiration from the consolidated table on BigQuery and is used for further operational analyses alongside a complete summary dashboard.
*   Main file: `Operational_Inventory_&_Supplier_Analysis.xlsx`

The file covers 4 sheets with different objectives:
*   **01_Data_Mart_Raw:** The consolidated table exported from BigQuery is strategically highlighted using conditional formatting to make products requiring intervention/correction stand out.
*   **02_Operational_Analysis:** A set of tables that extract data from the source table `tbl_InventorySupplier` to find further business information related to stock health, average price per category, reorder budget estimation, etc.
*   **03_Executive_Dashboard:** A dashboard that clearly and cleanly summarizes all the most relevant information found in the operational analysis phase, with a table chart summarizing the overall health of the business.
*   **PivotData:** Support sheet for the Dashboard containing the Pivot tables used as a source for the Charts.

**reports:**
Collection of final documentation:
*   Summary report on the procedure carried out via SQL.
*   Summary report of the data derived from the Excel file.

## Context, Execution, and Results

**Phase 1: Exploratory Auditing**
I analyzed the two source tables (`internal_inventory_raw` and `supplier_feed_raw`) to classify their problems, without modifying them.
The results on the internal inventory were:
*   8 SKUs with spaces (trailing, leading, or internal)
*   5 missing values on `category` and 5 on `reorder_point`
*   8 anomalies on retail prices: 4 prices equal to zero and 4 negative
*   3 duplicate SKUs with conflicting data (prices or categories in conflict)
*   8 duplicate `product_name`s associated with different SKUs

While the supplier feed presented:
*   10 casing errors on SKUs (e.g., `sku-1015` instead of `SKU-1015`)
*   5 SKUs not present in the internal inventory (from SKU-9991 to SKU-9995)

**Phase 2: Audit Logs**
The auditing results were framed in two persistent tables (`internal_inventory_audit_log` and `supplier_feed_audit_log`). Each anomalous row receives a textual description of the detected anomalies. These logs serve as an operational checklist for the cleaning phase and remain available for any subsequent checks.

**Phase 3: Cleaning**
I applied mechanical corrections where possible and flagged cases requiring human judgment for manual review.
For the internal inventory:
*   SKUs normalized (uppercase and spaces removed)
*   Missing categories replaced with the sentinel value `'Unknown'`
*   Invalid prices (zero or negative) set to NULL
*   Missing `reorder_point`s imputed to the default value 15
*   Duplicates resolved by choosing the row with the highest priority (valid price, then valid category, then highest stock)

For the supplier feed:
*   SKUs normalized for casing
*   The 5 orphan SKUs were kept and flagged for manual review

**Phase 4: Data Mart**
The `inventory_supplier_consolidated` table joins the cleaned data from the two systems via a `FULL OUTER JOIN` on the SKU.
The table calculates operational metrics (margin, stock health status, fulfillment routing) and assigns a severity status to each row (CRITICAL, WARNING, HEALTHY, N/A). Missing values are handled differently: missing stock becomes zero, missing prices remain NULL to avoid incorrect calculations.

**Phase 5: Excel**
The final step uses the Excel file to translate the data mart data into business decisions. The spreadsheet aggregates the states already classified in SQL, adding a single control column for the 16 duplicate product names.
From the cross-analysis of margins, stock, and categories, the report isolated the following critical issues and corrective actions still to be completed:
*   **Negative margins:** Suspend sales and update price lists for 9 SKUs generating a net loss of €16,898.
*   **Missing prices:** Insert retail prices for 13 SKUs, unlocking €78,516 of tied-up capital and making the supplier stock (which is already purchasable) sellable.
*   **Reorder plan:** Execute purchases for €268,504 (86% is immediately fulfillable), planning backorders for the 1,044 units in supplier shortfall and giving absolute priority to the 14 Electronics items below threshold.
*   **Supplier risk:** Diversify suppliers or negotiate safety stocks for high-leverage categories like Toys and Beauty, currently too dependent on dropshipping.
*   **Catalog anomalies:** Map the 5 orphan codes (present only at the supplier) and reconcile the 16 duplicate product names.

## How to use the project

Brief guide on how a user can explore the work:
*   Check the `bigquerySQL/` folder to understand the cleaning and audit logic applied to the data.
*   Verify the starting datasets in `bigqueryData/`.
*   Open the file in the `excel/` folder for operational details.
*   Read the documents in `reports/` for conclusions and key metrics.

## Author

*   **Name:** Julia Gasecka
*   **Role:** Data Analyst/Operations Analyst
