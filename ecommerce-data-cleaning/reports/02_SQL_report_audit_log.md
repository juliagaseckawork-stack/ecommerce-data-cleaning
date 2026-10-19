# Creation of Audit Logs: internal_inventory_audit_log and supplier_feed_audit_log

I wrote these queries to create the two persistent audit logs on the BigQuery project `ecommerce-analysis-503909`. The objective here is different from the exploratory audit: I no longer need to just look at the data and perform on-screen counts, but rather crystallize anomalies into actual tables that the cleaning phase will use as an operational checklist.

## The Shift in Approach: From Exploratory to Persistent

To understand the choices, one must keep in mind that these are not new queries, but a rewrite with a completely different objective. In the exploratory audit phase, I ran many small queries to get on-screen results and classify problems. Here, instead, I need a persistent table in the `staging` dataset, with one row for each anomalous row and a complete description of the problem. The audit is re-runnable and serves me to understand; the log is executed only once and serves the cleaning phase as a work base.

I used `CREATE OR REPLACE TABLE` in the `staging` dataset. The `CREATE OR REPLACE` makes the script idempotent: if I rerun it, it doesn't fail due to an existing table and doesn't accumulate with old data. The log must always reflect the current state of the raw data. The `staging` dataset helps me maintain layer separation: the log is an intermediate artifact, it doesn't touch the raw data but isn't yet a clean table.

In the audit phase, I separated queries to better explore the data, but here each separate query would cost a full table scan. Therefore, I concentrated everything into a single query per table, using a single CTE `calculated_anomalies` that calculates counts, flags, and joins. It is the maximum expression of the concept of "one scan pass for N flags": a source row enters and exits with its complete description of anomalies.

## The Flagging Pattern and the Unique String

I reused the `ARRAY_TO_STRING` pattern combined with `IF` statements that I had used in the audit, but here the motivation is strengthened. In the log, concatenation into a single string is the final product. A row with 4 anomalies produces a string like `'space in SKU | null category | negative price'` in a single `anomaly_description` column.

I could have used an `ARRAY<STRING>` type column, which would have been more structurally correct and filterable with `UNNEST`. I chose the string because the log must be readable by a human who reviews anomalies before cleaning. The separator `' | '` makes the string parsable if needed, and the array would complicate consumption by the cleaning phase without bringing any practical benefit.

I also added a double defensive filter at the end: `WHERE anomaly_description IS NOT NULL AND anomaly_description != ''`. It seems redundant because `ARRAY_TO_STRING` of an all-NULL array returns an empty string and never NULL, but it is defense in depth. If in the future the column were populated differently, the filter remains correct. I prefer to repeat the control rather than blindly rely on the current behavior of a single function.

Finally, I ordered the table at creation time with `ORDER BY anomaly_description`. Whoever materializes the log opens and reads it, and alphabetical ordering visually groups rows with the same first anomaly. In the supplier file, I also add `, sku` as a second key. It is a courtesy order for human inspection, not a technical constraint.

## Orthogonality of Flags and NULL Management

A principle I applied everywhere is the orthogonality of flags: each anomalous condition has its own dedicated flag, and no row can produce two flags describing the same problem.

For numeric flags, I wrote things like `IF(retail_price < 0, 'negative price', NULL)` without putting the guard `IF(x IS NOT NULL AND ...)`. It works because in SQL `NULL < 0` returns NULL, and the `IF` goes to the else branch returning NULL. A NULL price is never flagged as "negative price," but is captured by the dedicated check `'null retail_price'`. If I had put explicit guards everywhere, I would have only risked creating redundant and overlapping flags. The same applies to `IF(reorder_point <> 15, 'wrong reorder point', NULL)`: NULL already has its flag, so the value check can remain bare.

In the supplier file, there is also a composite rule that wasn't in the audit: `IF(s.supplier_stock > 0 AND (s.wholesale_cost IS NULL OR s.wholesale_cost <= 0), 'stock present with invalid cost', NULL)`. The validity of the cost here is conditioned by the presence of stock. Its position in the array, after the checks of individual fields, is not random. The order of elements determines the order of flags in the final string, and I chose an order that reflects the reading logic: first anomalies of individual fields, then those derived from their combination.

## Specific Choices for the Internal Table

![Internal AuditLog](images/Internal%20AuditLog.png)

For duplicates, I used window functions both as support columns and inline. I defined `sku_dup_count` as a column, but I also recalculated `COUNT(*) OVER(PARTITION BY sku)` inside the `IF` of the flag. It seems like duplication, but BigQuery does not allow referencing an alias from the same SELECT list inside another expression. I could have used an external subquery or a double CTE, but I would have only added nesting levels. I chose this slight redundancy because the BigQuery engine optimizes partitioning by calculating it only once, and in exchange, I have both the concatenated flag and a count column useful for investigation.

On this check, I put a fundamental guard: `sku IS NOT NULL AND`. Without this, all rows with NULL SKU would end up in the same partition (because NULL does not distinguish) and would be flagged as duplicates. With the guard, NULL SKUs are classified only as `'null SKU'`.

Another targeted choice is to partition on the raw SKU and not on `UPPER(TRIM(sku))`. In the audit, I normalized to find logical duplicates, but in the log, spaces are already flagged separately as `'space in SKU'`. If I normalized in the partition, a pair with and without space would give only "duplicate," losing the more precise information of the space. By partitioning on the raw data, flags remain orthogonal and cumulative.

Furthermore, the flag `'duplicate ... record'` is applied to all rows in the group, without distinguishing the original from the copy. The log documents, it does not judge. There is no reliable criterion to designate the good row a priori, since the duplicates we found had conflicting data on different columns. The choice of the surviving row belongs to the cleaning phase, and the log must present them all with the same level of suspicion.

## Specific Choices for the Supplier Table

![Supplier AuditLog](images/Supplier%20AuditLog.png)

The most significant divergence from the audit is in the cross-system integrity check. In the audit, I had used `UNION ALL` + `COUNTIF` because I needed an aggregated classification robust to duplicates. Here the objective is different: I only need to mark each row in the supplier with a binary label (exists in internal yes/no). For a row-level label, the `LEFT JOIN` is the natural tool.

I performed the join by normalizing SKUs with `UPPER(TRIM())` in the condition. The `LEFT JOIN` preserves all rows in the supplier, including those without matches which are precisely the orphans. The orphan condition becomes simply `i.sku IS NULL`.

I know that the one-to-one join exposes the risk of fan-out: the 3 duplicate SKUs in internal generate multiplied rows for the supplier. The union pattern of the audit was immune to this, but here the risk is contained. The previous audit already told me that internal duplicates are 3 and known, and the multiplication is effectively informative. Above all, the log query never aggregates on the result of the join, so fan-out does not corrupt counts, producing at most repeated rows in the log that are detectable and harmless. The general principle I followed is that the pattern depends on the semantics of the result: aggregated classification requires unions and counts, row labeling requires the join.

To prevent SKUs with NULL in the supplier from being flagged as orphans (since the join wouldn't find a match and `i.sku` would still be NULL), I put the double guard `s.sku IS NOT NULL AND i.sku IS NULL`.

I also condensed the casing check into a single boolean expression. Instead of a sequential `CASE WHEN`, I used `REGEXP_CONTAINS` case-insensitive AND NOT case-sensitive. It is more compact and adapts better to the context of the log's `IF`, where I only need to know that the row needs fixing without having to distinguish two different categories.

For internal spaces, I simplified the regex to `r'\s+'` compared to the `r'\S\s+\S'` of the audit. It is intentionally more restrictive: in the log, I want to capture any presence of whitespace in the SKU, delegating the distinction between internal and external to the two separate checks.

Finally, I merged the cost checks. In the audit, I separated `'negative cost'` and `'zero cost'` because they had diagnostic value. In the log, the remediation is identical (the cost must be verified or recalculated), so a single flag `'wrong cost (<=0)'` suffices and simplifies reading. I used aliases `s` and `i` to qualify each column and eliminate any ambiguity on the sides of the join.

## What I Inherited from the Audit and What I Cut

Comparing the two levels, the log is not a copy of the audit but a selection guided by results. I inherited all families of anomalies that we had actually detected, such as spaces, NULLs, placeholders, duplicates, invalid prices, and cross-system orphans. I added the composite rule on stock with invalid cost, which is an evolution possible only after seeing the data.

Instead, I cut purely exploratory checks from the audit, such as name lengths or extreme prices per category. In a log of confirmed anomalies, they make no sense because they do not produce rows to fix. The log freezes in persistence what needs correction, and the cleaning phase will consume these tables in the `staging` dataset as an operational checklist.