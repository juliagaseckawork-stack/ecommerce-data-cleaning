# Data Mart: inventory_supplier_consolidated

I wrote this query to create the `inventory_supplier_consolidated` data mart on the BigQuery project `ecommerce-analysis-503909`. This is the final level of the pipeline, the one that transforms clean data into operational and financial intelligence. The fundamental difference from the staging tables is that here I no longer describe the data, but rather express judgments and prescriptions. In staging we had correct data and a worklist for those who needed to clean it. Here we have calculated metrics, health statuses, and operational routing. The temporal naming, with prefixes like `current_supplier_cost`, declares that this table is a snapshot of the current state, without historical dimension. Anyone reading it knows that these margins are the current ones.

![Data Mart](images/Data%20Mart.png)

## The Join and Preservation of the Three Worlds of the Catalog

The join at this stage is not only admissible, but made safe by the upstream work. During the cleaning phase, I ensured that both input tables have exactly one row per key. The risk of fan-out that led me to discard the join in favor of unions and counts during the audit phases is completely eliminated here. And I specifically need the join because I must place the internal price and supplier cost on the same row to calculate the margin. With a union, the two measures would end up on different rows and the calculation would be impossible.

I used a `FULL OUTER JOIN` between `internal_inventory_cleaned` and `supplier_feed_cleaned` on SKU. The choice derives from the analytical objective: the table must represent the entire unified catalog, which divides into three distinct populations. There are products matched in both systems, where margins and stock dynamics live. Then there are internal-only products, items without a mapped supplier. Finally, there are supplier-only products, the orphans that I deliberately preserved during the cleaning phase.

If I had used an `INNER JOIN`, the supplier orphans would have disappeared silently, representing an enormous loss of information since they could be new products not yet cataloged. The `FULL OUTER JOIN` is the only coherent choice: orphans find their analytical placement here and no information dies along the pipeline.

For the consolidated key, I used `COALESCE(i.sku, s.sku)`. In a full outer join, the unmatched side has a NULL key, and `COALESCE` guarantees that `consolidated_sku` is always populated. This guarantee holds because both input tables already filtered out NULL and empty keys during the cleaning phase. The only way a key can be missing here is due to lack of match between the two systems, not because the key is dirty. Note also that I compare keys directly, without normalizing them with `UPPER(TRIM())` as I did in the audit on raw data: normalization is inherited from cleaning, not repeated.

## How I Handled Missing Values

Here too I applied the same guiding principle from the cleaning phase: the treatment of missing values depends on the semantic type of the data.

For stock, I used `COALESCE(i.internal_stock, 0)` and `COALESCE(s.supplier_stock, 0)`. If stock is missing from one of the two sources, it means that source has no availability. The absence of the row implies zero stock from that side, and zero is the neutral element of addition. If I had left the NULLs, the sum to calculate total availability would have become NULL, losing the only calculable quantity.

The opposite applies to price. If the selling price or cost is missing, I left the NULLs. A missing price means "I don't know," not "the price is zero." Calculating a margin on an invented price of zero would produce a false measure. NULL maintains explicit ignorance, and downstream controls, such as margin health status, correctly intercept this lack. Additive quantities to zero, monetary measures to NULL: it's the same matrix from previous phases, extended to the join context.

## CASE Chains as Business Rules

The analytical core of the query lies in three `CASE` chains for integration status, margin health, and stock health, plus a fourth for operational routing. They share a structure I applied intentionally: the `WHEN` clauses are ordered by decreasing severity, conditions are mutually exclusive, and coverage is exhaustive.

The order of the `WHEN` clauses is not a matter of form, but of substance. SQL evaluates conditions sequentially and exits at the first match, so the order encodes a priority hierarchy. In each chain, I placed critical conditions first, then warnings, then healthy status, and finally the residual. Thus, a row satisfying multiple conditions gets labeled with the most severe.

Take the margin chain. The first branch checks if the margin is negative. Logically this would be redundant, since a negative margin is also below 20% from the second branch. I kept it separate because I didn't want to classify it as simply a low margin, but as a critical negative margin. The separation exists to give severity precedence over logical completeness.

I used `SAFE_DIVIDE` instead of the classic division operator. If the price is NULL or zero, it returns NULL instead of causing the query to error. Prices less than or equal to zero were already zeroed to NULL during cleaning, so division by zero is effectively impossible, but the defense remains for robustness. The comparison for low margin is against `0.20` and not `20`, because `SAFE_DIVIDE` returns the pure ratio. Comparing the ratio avoids duplicating the multiplication by one hundred in the predicate. Furthermore, the margin base is the retail price: it's the margin on revenue, the standard financial metric, and 20% reads as "for every euro sold, at least twenty cents of margin."

## Stock Health and Reorder Point

The stock chain is the most articulated. The order encodes this decision hierarchy: first null availability, distinguishing whether it's recoverable from the supplier or not, then the reorder threshold, then healthy availability, and finally the residual.

The interesting detail is what happens when supplier stock is zero and internal stock is greater than zero but below the reorder point. The row ends up in the healthy availability branch. I accepted this simplification because availability status takes precedence over the reorder threshold. The reorder point is a preventive alarm, not a factual state. As long as there is internal stock, the product is sellable. The warning only makes sense when there exists a reorder alternative from the supplier that makes it actionable. When the supplier is at zero, warning to reorder would be an unexecutable instruction. The CASE structure therefore reflects not only severity but also the operability of the alert.

For the guard on the reorder point, I wrote `i.reorder_point IS NOT NULL`. In the cleaned table, the reorder point has already been imputed to 15, so it cannot be NULL. The guard remains because the chain should not depend on a property of another pipeline phase. If tomorrow the imputation rule changed, the data mart wouldn't break.

## Operational Routing and Naming Conventions

The last CASE chain generates the `recommended_fulfillment_route` column. This is the column that qualifies the table as operational: it doesn't describe the state, it prescribes action. The three labels map availability states onto a two-channel logistics model: internal stock means direct fulfillment, supplier-only stock means dropship, nothing anywhere means not sellable.

I put this logic in the output as a column, rather than leaving it to be calculated downstream in BI. This way I encode the fulfillment policy once, at the pipeline level. All consumers apply the same rule, without interpretation drift. The routing doesn't consider margin—a dropshipped product might be sold at a loss—but I kept the two logics separate in distinct columns because they are different questions. Placing them side by side in the same row, readers can easily cross-reference them.

For naming, I embedded severity directly in the label text, making them start with CRITICAL, WARNING, HEALTHY, or N/A. Beyond readability, this makes labels sortable and filterable alphabetically in any downstream tool, without needing a separate severity column. I also made units and semantics explicit in column names, distinguishing absolute amounts from percentages, and applied `ROUND(..., 2)` to amounts and percentages to maintain two-decimal compliance verified in the audit.

Finally, I ordered the output with `ORDER BY catalog_integration_status DESC, consolidated_sku ASC`. The descending order puts supplier-only products at the top of the table. It's the same courtesy ordering used throughout the pipeline, but here with analytical function: anyone with pending doubts or unmapped products sees them first.

Looking at the evolution of the pipeline, the role of joins and keys has changed consistently with the semantics of each phase. In cross-source audit I used unions and counts on normalized keys to robustly classify orphans and duplicates. In the supplier audit log, I moved to a left join on raw data to document the current state row by row. In supplier cleaning, the left join occurred on the cleaned table to verify referentiality against valid state. Here in the data mart, the full outer join on cleaned data unifies the two worlds for comparison. Four different integration techniques for four different semantics. The orphans found in the audit are the same ones that cleaning preserved and that emerge here as supplier-only: a single data story traverses the four tables without ever getting lost.