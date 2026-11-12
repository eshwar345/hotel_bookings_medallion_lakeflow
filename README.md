# Hotel Bookings Medallion Pipeline

A Lakeflow Spark Declarative Pipeline (SDP) implementing the Medallion Architecture
(Bronze -> Silver -> Gold) for hotel booking analytics.

## Project structure

```
ETL_Pipeline/
├── Bronze_layer/
│   └── Bronze.sql     # Streaming ingestion of raw CSV bookings via Auto Loader
├── Silver_layer/
│   └── Silver.sql     # Cleaned bookings (data quality expectations) + rejected rows
└── Gold_layer/
    └── Gold.sql       # Business summary tables + data quality reconciliation
dashboard/
└── Hospitality_Bookings_Insights_2025.lvdash.json   # AI/BI dashboard (importable)
```

## Pipeline configuration

| Setting | Value |
| --- | --- |
| Pipeline name | hotel_bookings_medallion_pipelinee |
| Catalog | hospitality_catalog |
| Schema | bookings |
| Trigger | Manual (development: false, continuous: false) |
| Photon | Enabled |
| Serverless | Enabled |

## Datasets

- `bronze_hotel_bookings` (streaming table): raw CSV ingestion from
  `/Volumes/hospitality_catalog/bookings/raw_files/` via `read_files` Auto Loader,
  enriched with `source_file` and `loaded_at`.
- `silver_bookings_clean` (materialized view): deduplicated, standardized bookings.
  Expectations (drop rows): valid_stay_dates (check_out > check_in), valid_room_rate (rate >= 0).
- `silver_bookings_rejected` (materialized view): rejected rows with reject_reason.
- Gold tables: `gold_monthly_bookings`, `gold_hotel_summary`, `gold_room_type_summary`,
  `gold_channel_summary`, `gold_data_quality` (reconciliation check).

## Data quality reconciliation (2025 dataset)

Bronze rows: 1,316 | Clean: 1,269 | Rejected: 21 | Duplicates: 26 | Passed: Yes

## How to deploy

1. Create a Lakeflow Spark Declarative Pipeline with catalog `hospitality_catalog`, schema `bookings`.
2. Add the `ETL_Pipeline` folder as the pipeline source (library glob `ETL_Pipeline/**`).
3. Ensure the raw CSV files exist under `/Volumes/hospitality_catalog/bookings/raw_files/`.
4. Run the pipeline (Start update). Full refresh reprocesses everything from scratch.

## Dashboard

Import `dashboard/Hospitality_Bookings_Insights_2025.lvdash.json` via
Dashboards -> Create dashboard -> Import dashboard JSON.
