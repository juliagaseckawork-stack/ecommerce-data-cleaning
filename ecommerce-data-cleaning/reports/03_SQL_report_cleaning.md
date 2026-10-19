# Data Cleaning: internal_inventory_cleaned and supplier_feed_cleaned

I wrote these queries to create the clean tables on the BigQuery project `ecommerce-analysis-503909`. This is the final phase of the pipeline, the one that takes raw data and prepares it for use. The rule I set for myself is very simple: if an error can be corrected mechanically and with certainty, I fix it. If instead it requires human judgment or there are missing data that I cannot invent, I leave the value as is (or set it to NULL) and mark it for manual review.

## Execution Order and Raw Data

I had to execute the internal inventory file first and then the supplier one. This is not a matter of convenience, but a direct technical dependency: the supplier query performs an integrity join precisely against the `staging.internal_inventory_cleaned` table. If I hadn't created that first, the supplier join would have pointed to nothing.

Throughout this process, the `raw_data` tables remained rigorously intact. I always read from raw and write only to staging, so if I need to rerun the pipeline from scratch, the audit logs remain valid and reproducible.

## Cleaning Decisions for Each Column

To decide how to treat each column, I looked at what the audit found and reasoned about the data type.

For `sku`, I applied `UPPER(TRIM())` because it's a mechanical and reversible normalization on a key. For `product_name`, however, I did nothing: it's descriptive text, not a key, and I preferred to preserve the original.

For `category`, which had NULLs, I used a `CASE` statement to insert the sentinel value `'Unknown'`. Being a dimension, I needed it to remain aggregatable in `GROUP BY` operations without silently losing rows. The opposite applies to `retail_price`: if the price was less than or equal to zero, I replaced it with NULL. I cannot invent a selling price, so NULL clearly indicates that the data is missing, without corrupting numerical aggregations.

For `internal_stock`, I didn't touch anything because the audit hadn't found anomalies. Finally, for `reorder_point`, I used `COALESCE(..., 15)`. In this case, the imputation is legitimate because 15 is a known and verified business default.

The difference between putting `'Unknown'` in the category and NULL in the price depends on the data type. `'Unknown'` works well for dimensions because it participates in groupings, while NULL is correct for measures because it is cleanly excluded from functions like `AVG` or `SUM`. Using `'Unknown'` for a price would destroy averages, and using NULL for a category would make it invisible to reports.

## Recurring Patterns

In all queries, I used a renaming trick. In the first CTE, I create aliases with the prefix `clean_` (like `clean_sku`), and then in the final SELECT I rename them by removing the prefix. This helps me disambiguate: in intermediate CTEs, I need to be able to compare the cleaned price with priority rules, and using the same name for the raw and cleaned versions would only create confusion. In the end, I return the canonical schema, so whoever consumes the table downstream doesn't need to know anything about my internal steps.

At the beginning of the queries, I put a filter `WHERE sku IS NOT NULL AND TRIM(sku) != ''`. This is the only point where I definitively eliminate rows from the clean table. A row without a primary key cannot participate in deduplication, cannot join with the other system, and there is no mechanical way to invent a SKU. Structurally, it's unmanageable, so I discard it, knowing that its trace still remains documented in the audit logs.

I wrote all transformations so they don't crash on NULLs. No casts or arithmetic operations on values that might be NULL. If a price is NULL, the condition `> 0` returns NULL and the `IF` leaves it quietly as NULL. A cleaning process that stops halfway because a row is dirty is worse than one that marks it and moves on.

I added two extra columns to both tables: `audit_notes` and `requires_manual_review`. `audit_notes` is the usual concatenated string with `ARRAY_TO_STRING` that explains why the row is suspicious. `requires_manual_review` is a boolean used for filtering. Keeping both is convenient: the boolean for making filters in Excel, the string for reading the context without having to cross-reference other tables.

I ordered the output with `ORDER BY requires_manual_review DESC, audit_notes ASC`. Rows requiring manual review thus end up at the top of the export. Whoever opens the file finds the worklist already ready, without having to filter.

## Specific Choices for the Internal Table

![Inventory Clean](images/Inventory%20Clean.png)

To resolve duplicates, I used `ROW_NUMBER` with partitioning on `clean_sku`. I didn't use `DISTINCT` or `GROUP BY` with `ANY_VALUE` because they would have chosen a row at random. With ranking, I can decide deterministically which row survives.

The priority order I set is: first rows with a valid price, then those with a valid category (different from 'Unknown'), and finally those with higher stock. I used the trick `IF(condition, 1, 0) DESC` in the ORDER BY to transform criteria into integers and make them explicit, avoiding the subtleties of how BigQuery orders booleans or NULLs. If two rows have the same valid price and the same valid category, I look at the stock, assuming that the higher one is the most recent data. It's a heuristic, but the row is still flagged for manual review, so the residual arbitrariness is covered.

To understand whether the deduplication hid a conflict, I added flags like `COUNT(DISTINCT clean_retail_price) OVER (PARTITION BY clean_sku) > 1`. If the duplicate rows had different prices (like SKU-1015), the flag turns on. This way, whoever reviews knows that I had to arbitrate the choice, and it wasn't a perfect duplicate. The `COUNT(DISTINCT)` works on already cleaned values, so a conflict between a valid price and one that I zeroed to NULL is not signaled as a conflict.

Deduplication occurs after normalizing the key. First, I do `UPPER(TRIM(sku))` in the cleaning CTE, and only then do I partition by `clean_sku`. If I deduplicated on the raw key, I would miss all duplicates that differ only by spaces or capitalization.

In the `CASE` for the category, I checked both `IS NULL` and `TRIM(category) = ''`. I needed to capture pseudo-NULLs as well, i.e., empty strings or strings of only spaces, otherwise they would pass as legitimate categories creating phantom groups.

## Specific Choices for the Supplier Table

![Supplier Clean](images/Supplier%20Clean.png)

Here is the proof that I am applying the rules to the letter. In the internal table, I did `UPPER(TRIM(sku))`, but here in the supplier I only did `UPPER(sku)`. The supplier audit had found 10 casing errors but zero space errors. So I only applied the fix for casing. I don't correct a problem I haven't measured, even though `TRIM` costs nothing in terms of computation. Every transformation on unverified data is a risk.

I performed the integrity join against `staging.internal_inventory_cleaned`, not against the raw table. If I had joined against raw, non-normalized keys would have generated false orphans due to spaces. If I had normalized on the fly, raw duplicates would have generated fan-out multiplying the rows. By joining against the cleaned table, I have the certainty of matching against the final and valid state of the inventory, with exactly one row per key.

I didn't eliminate supplier rows that don't find a match in internal. I kept them in the cleaned table, flagging `requires_manual_review` as TRUE. An orphan isn't necessarily an error: it could be a new supplier product not yet cataloged in our system. I preferred to maintain the information and let the business decide.

Numeric values like `supplier_stock` and `wholesale_cost` passed through cleaning without any modification. The audit hadn't detected anomalies on these fields, so I didn't touch them.