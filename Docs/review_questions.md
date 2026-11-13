# Project Review Questions and Answers

Answers to project review questions for the Hotel Booking Medallion Lakehouse platform, built using Lakeflow Spark Declarative Pipelines on Azure Databricks.

---

## 1. Why do we preserve raw data in Bronze instead of cleaning the source immediately?

Bronze is the system of record for what actually arrived. Keeping it unchanged gives us:

- **Traceability:** any cleaned value in Silver or Gold can be traced back to the original source record.
- **Reprocessability:** if a cleaning rule turns out to be wrong (for example, handling edge cases in date comparisons or missing discount calculations), we fix the rule and rebuild Silver and Gold from Bronze, without needing to re-request the original file.
- **Auditability:** we can show exactly what raw hotel booking rows were received, what was transformed, and why.
- **Safe experimentation:** new data quality constraints or feature engineering rules can be tested without risking the raw source data.

If we cleaned the source immediately, original raw values would be permanently lost, preventing us from auditing or reversing any data transformation decision.

---

## 2. What is the difference between a data-quality flag and rejecting a record?

| | Flag / Quarantine | Reject / Drop |
|---|---|---|
| What happens | The record is filtered out of clean trusted tables and routed to a dedicated quarantine view (e.g., `silver_bookings_rejected`) with an explicit failure reason | The record is entirely discarded without tracking or auditing *(not recommended)* |
| Use when | Physical or logical constraints fail (e.g., check-out date on or before check-in date, or negative room rates) | Records are structurally unparseable or completely corrupted |
| Risk | If not monitored, quarantined rows might sit unnoticed without operational feedback | Loss of visibility into bad upstream data quality issues |
| Reversible | Yes, by correcting the raw source or adjusting the validation criteria and running a full refresh | No, dropped data is gone forever |

In this project, physically invalid stay durations and negative rates are caught using expectations (`EXPECT ... ON VIOLATION DROP ROW`) and captured in `silver_bookings_rejected`, enabling precise data quality auditing.

---

## 3. Why is Booking ID alone potentially unsafe as a duplicate key?

While a unique `booking_id` typically identifies a distinct reservation, certain transactional streams or multi-room guest modifications can result in duplicate entry rows or overlapping transaction updates. Treating `booking_id` blindly without considering structural uniqueness across attributes like `guest_id`, `check_in_date`, and `hotel_name` could mask upstream recording errors.

Duplicates in our pipeline are evaluated using explicit distinct selection (`SELECT DISTINCT`) across core transactional attributes and audited via the `gold_data_quality` reconciliation layer to track exact duplication metrics.

---

## 4. How would you investigate a negative room rate or invalid stay dates?

1. **Isolate** the flagged rows in `silver_bookings_rejected` and compare them directly with the raw records in `bronze_hotel_bookings`.
2. **Check related fields:** do `check_in_date`, `check_out_date`, and `room_rate` logically conflict? For example, a check-out date preceding check-in indicates booking entry errors or system timestamp corruption.
3. **Look for patterns** by `hotel_name`, `booking_channel`, or `city`. A cluster points to a systematic integration or booking engine glitch, while isolated rows suggest manual user entry errors.
4. **Check for business explanations:** cancellations, special promotional adjustments, or test transactions.
5. **Decide and document:** keep in the rejection quarantine view, refine validation rules, and document updates in `docs/data_quality_rules.md`.
6. **Escalate** to upstream data providers or system administrators if the anomaly indicates structural database corruption.

The guiding principle is to ensure data integrity without blindly dropping valid edge-case records.

---

## 5. How can you prove that the Gold revenue total is consistent with the cleaned Silver data?

By running automated **reconciliation queries** embedded within the `gold_data_quality` materialized view:

- `SUM(net_revenue)` across Gold summary views must perfectly align with aggregate calculations derived directly from `silver_bookings_clean`.
- Row-count reconciliation must balance perfectly across layers: 
  $$\text{Bronze Total Rows} = \text{Silver Clean Rows} + \text{Silver Rejected Rows} + \text{Duplicate Rows}$$
- Re-running the pipeline or querying `gold_data_quality` yields a reconciliation pass flag (`reconciliation_passed = 'Yes'`), proving zero silent data loss.

---

## 6. What would change if new hotel booking files arrived every day?

- **Ingestion:** leverage Databricks Auto Loader (`read_files`) with streaming tables (`bronze_hotel_bookings`), which automatically discovers and ingests only newly arrived files from the Unity Catalog Volume.
- **Stateful Deduplication:** cross-batch deduplication becomes necessary to handle duplicate bookings arriving across different daily files.
- **Idempotency:** pipeline runs must remain strictly idempotent so that reprocessing historical files does not duplicate revenue figures.
- **Scheduling & Orchestration:** schedule Lakeflow pipelines to execute automatically upon file arrival or on a fixed cron schedule.
- **Monitoring & Alerting:** configure alerts for pipeline failures, schema drift, or sudden spikes in data rejection rates.
- **Gold Incremental Refreshes:** materialized views automatically update incrementally, avoiding full table rebuilds and keeping the executive dashboard current.

---

## 7. When would you introduce separate customer and hotel dimension tables?

When the flat analytical model begins to show limitations:

- Customer profiles or hotel metadata (`city`, `region`, star ratings) are **repeated** across thousands of booking rows and require centralized master data management.
- Multiple downstream fact tables (e.g., bookings, cancellations, loyalty rewards) need to share **consistent** entity definitions.
- You need to track **historical attribute changes** over time (Slowly Changing Dimensions, such as a hotel changing regions or tier categories).
- Business analysts require a structured **star schema** for optimized BI tool performance and complex joins.

For our current dataset scope, a streamlined denormalized model combined with aggregations is sufficient; dimensional modeling represents a natural Phase 2 scaling step.

---

## 8. How could this batch pipeline evolve toward incremental or streaming processing?

1. **Incremental Lakeflow Processing:** utilize streaming tables for Bronze and incremental materialized views for Silver and Gold layers, which is already foundational to our current architecture.
2. **Micro-batch streaming:** configure continuous streaming triggers to process incoming reservation events with near real-time sub-minute latency.
3. **Event-driven architecture:** transition file drops to message brokers or event hubs (such as Kafka) streaming real-time booking actions.
4. **State Management:** implement watermarking and stateful stream-to-stream joins to handle late-arriving booking modifications or cancellations gracefully.
5. **Production Maturity:** establish rigorous CI/CD deployment workflows, automated data testing frameworks, and strict SLA monitoring.

Phase 1 intentionally establishes a robust, declarative batch foundation to validate business logic and data hygiene before introducing real-time stream complexity.
