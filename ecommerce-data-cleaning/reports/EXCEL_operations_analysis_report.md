# Operational and Decisional Report: Inventory & Supplier Analysis

## File Architecture and Connection with the Pipeline

The Excel file is structured as a decision-making pyramid. Each sheet answers a specific question, and the navigation order replicates the logic of the data pipeline we built on BigQuery.

The first sheet exports the raw data from the data mart to see what the data says row by row. The second sheet contains the operational analysis to understand where the problems are and how much they cost, aggregating the statuses created in SQL. The third sheet is the executive dashboard that translates everything into economic decisions. The last sheet is a technical support cache for pivot tables.

The connection point with BigQuery is explicit: Excel does not recalculate anything new. It simply groups and recalculates what the CASE chains in the SQL query have already classified. This is the operational proof of the choice to encode severity directly into the data mart values.

There is only one column calculated directly in Excel and not present in the SQL data mart: `duplicate_name`. This serves to mark 16 SKUs as duplicate product names and acts as a link to the cleaning phase, where 8 duplicate names with different SKUs had been flagged. The choice to calculate this at the report level rather than in the SQL table is precise: it is a catalog warning, not a structural data anomaly.

## Margin Audit: Financial Health and Blocked Capital

![Margin Audit](images/Margin%20Audit.png)

Moving to the results of the Margin Audit in the second sheet, the catalog shows an average margin of 49.09%, indicating overall good financial health. Here is how the retail value of nearly 9 million euros is distributed:

*   **MARGIN OK:** 483 SKUs for 116,575 units of stock, generating €8,871,134 in retail value and €4,508,588 in net profit.
*   **CRITICAL Negative margin:** 9 SKUs for 2,168 units, with €118,446 in retail value but a net loss of €16,898. An emblematic case is Chanel No. 5, which requires immediate suspension of sales.
*   **N/A Missing price:** 13 SKUs for 2,621 units. The retail value is zero, but they represent €78,516 of supplier stock already purchasable.

These 13 items with missing prices are not a loss, but blocked capital. This is the direct result of the choice made during the cleaning phase to set invalid prices to NULL instead of inventing a value. Ignorance about the data is now explicit and has a precise price, allowing the business to quantify exactly the stationary merchandise. The general total closes with 505 SKUs, 121,364 units of stock, €8,989,581 in retail value, and €4,413,174 in potential net profit.

## Stock Health and the Realistic Reorder Budget

![Stock Health](images/Stock%20Health.png)

On the Stock Health front, the catalog counts 25,438 internal units. The distribution by health status is as follows:

*   **HEALTHY AVAILABILITY:** 423 SKUs with 24,905 units, managed with internal fulfillment.
*   **WARNING Below reorder point:** 70 SKUs with 533 units, still managed internally but below the reorder threshold.
*   **CRITICAL Internal stockout:** 12 SKUs with 0 internal units, requiring activation of dropship routing.

The theoretical reorder budget requires interventions on 82 SKUs for a total of 7,667 units, for a value of €287,473.72. The most refined operational choice in the file was to cross-reference this theoretical budget with the supplier's actual stock to create an Actionable Reorder Budget. From this cross-reference emerges the true feasibility of the plan:

![Realistic Reorder Budget](images/Realistic%20Reorder%20Budget.png)

*   **Full Coverage:** 61 SKUs for a theoretical need of 5,679 units, all fulfillable immediately with zero shortfall and 100% coverage.
*   **Partial Coverage:** 21 SKUs for a theoretical need of 1,988 units, of which only 944 are fulfillable immediately, leaving a shortfall of 1,044 units and partial coverage of 47.5%.
*   **Total Real:** 82 SKUs for 7,667 theoretical units, of which 6,623 are fulfillable and 1,044 are in shortfall, for an overall capacity of 86.38%.

The key data in the executive sheet confirms the exact reconciliation: the theoretical budget of €287,473.72 minus supplier constraints gives us an Executive Reorder Budget of €268,503.60. Supplier stock thresholds have effectively protected €18,970.12 in liquidity. The theoretical demand is not immediately fulfillable for 13.6% because the supplier itself does not have the available units, and these 1,044 units must be managed with backorders.

## Category Intelligence: Where Money and Risks Move

![Category Intelligence](images/Category%20Intelligence-1.png)

The category analysis applies the methodological choice of weighted margin on inventory value, weighting categories in proportion to the capital actually immobilized. Here is the complete detail:

**Electronics**
*   Internal Stock Value: €358,842
*   Weight: 36.4%
*   Weighted Margin: 56.2%
*   Reorder Alerts: 14
*   Leverage Ratio: 4.92
*   Price Tier: High Ticket (avg €251)

**Kitchen**
*   Internal Stock Value: €114,337
*   Weight: 11.6%
*   Weighted Margin: 48.4%
*   Reorder Alerts: 12
*   Leverage Ratio: 4.89
*   Price Tier: Medium

**Clothing**
*   Internal Stock Value: €122,335
*   Weight: 12.4%
*   Weighted Margin: 43.8%
*   Reorder Alerts: 12
*   Leverage Ratio: 4.24
*   Price Tier: Medium

**Beauty**
*   Internal Stock Value: €113,315
*   Weight: 11.5%
*   Weighted Margin: 43.8%
*   Reorder Alerts: 8
*   Leverage Ratio: 5.12
*   Price Tier: High Ticket (avg €75)

**Home**
*   Internal Stock Value: €94,310
*   Weight: 9.6%
*   Weighted Margin: 46.2%
*   Reorder Alerts: 9
*   Leverage Ratio: 4.54
*   Price Tier: Medium

**Toys**
*   Internal Stock Value: €69,227
*   Weight: 7.0%
*   Weighted Margin: 42.0%
*   Reorder Alerts: 7
*   Leverage Ratio: 5.25
*   Price Tier: Low

**Sports**
*   Internal Stock Value: €69,475
*   Weight: 7.1%
*   Weighted Margin: 49.4%
*   Reorder Alerts: 6
*   Leverage Ratio: 4.52
*   Price Tier: Medium

**Books**
*   Internal Stock Value: €37,003
*   Weight: 3.8%
*   Weighted Margin: 46.3%
*   Reorder Alerts: 9
*   Leverage Ratio: 4.70
*   Price Tier: Low

**Unknown**
*   Internal Stock Value: €6,498
*   Weight: 0.7%
*   Weighted Margin: —
*   Reorder Alerts: 0
*   Leverage Ratio: 4.23
*   Price Tier: —

Electronics is clearly the engine of the business, representing over a third of the inventory value and having the highest weighted margin. The 14 reorder alerts in this category make it the absolute priority for budget allocation. On the other hand, categories like Toys and Beauty show maximum leverage ratios, respectively 5.25 and 5.12. These are categories structurally dependent on dropshipping, and when the supplier is in crisis, they are the first at risk of out-of-stock.

## Executive Dashboard: The Business Summary

![Dashboard Excel](images/Dashboard%20Excel.png)

The third sheet closes the loop with the main KPIs and the Health Audit Table, which maps each row to a decision taken in the previous phases of the pipeline. The summary KPIs tell us that we have €985,341 of capital in internal inventory (25,438 units) compared to supplier stock of €4,576,407 (121,364 units), which is about 4.8 times our inventory. The potential net profit is €4,413,174, the realistic purchase plan is worth €268,504, and the liquidity protected by supplier constraints is €18,970.

The Health Audit Table translates everything into concrete actions, summing the populations until reaching exactly the 505 total SKUs of the data mart:

**HEALTHY OK**
*   SKU: 368
*   Internal Value: €873,025
*   Recommended Action: Standard operations
*   Pipeline Origin: —

**ATTENTION Low Stock (Full Cvg)**
*   SKU: 61
*   Internal Value: €15,408
*   Recommended Action: Activate PO at 100%
*   Pipeline Origin: Reorder point = 15

**ATTENTION Low Stock (Partial Cvg)**
*   SKU: 21
*   Internal Value: €3,929
*   Recommended Action: Max order 944 u. + backorder
*   Pipeline Origin: Supplier constraints

**WARNING Internal Stockout**
*   SKU: 12
*   Internal Value: €0
*   Recommended Action: Enable dropship routing
*   Pipeline Origin: Fulfill via dropship

**WARNING Missing Price**
*   SKU: 13
*   Internal Value: €7,440
*   Recommended Action: Insert retail price
*   Pipeline Origin: retail_price → NULL

**CRITICAL Negative Margin**
*   SKU: 9
*   Internal Value: €27,957
*   Recommended Action: Suspend sales, update price list
*   Pipeline Origin: —

**UNMATCHED Supplier Only**
*   SKU: 5
*   Internal Value: €0
*   Recommended Action: Map codes in the catalog
*   Pipeline Origin: Orphan SKUs 9991...9995

**DUPLICATE Product Name**
*   SKU: 16
*   Internal Value: €57,583
*   Recommended Action: Reconcile homonymous records
*   Pipeline Origin: Duplicates by name

No row of the data mart is uncovered, and no population has been lost along the path.

## The 5 Operational Decisions on Data

From all this data emerge five immediate business decisions to take:

1.  Urgent intervention on the prices of 9 SKUs that generate negative margins for a total of €16,898, suspending their sales and updating the price lists.
2.  Unlock €78,516 of blocked capital by inserting the 13 missing prices to make the supplier stock that is already purchasable sellable.
3.  Execute reorders for €268,504, knowing that 86.38% is immediately fulfillable, planning backorders for the 1,044 units in shortfall, and giving absolute priority to the 14 Electronics SKUs that are below threshold.
4.  Guard high-leverage categories like Toys and Beauty by negotiating safety stocks or diversifying suppliers, since sales continuity in these categories depends entirely on their availability.
5.  Close catalog anomalies by mapping the 5 orphan codes into the internal system and reconciling the 16 duplicate product names.