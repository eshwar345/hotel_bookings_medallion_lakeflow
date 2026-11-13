# Data Quality Rules

This document describes the data-quality (DQ) rules applied in the **Hotel Booking Medallion Lakehouse** pipeline, how each anomaly is treated, and where it is enforced across layers.

> **Principle:** Raw data is never modified. Issues are isolated, imputed according to explicit business rules, or quarantined into a dedicated rejection table (`silver_bookings_rejected`). Every exclusion is counted and reconciled in `gold_data_quality`.

---

## 1. Known Issues in the Source Data

The raw source file (`hotel_bookings_raw.csv`, 1,316 rows) contains realistic operational data quality anomalies:

| # | Issue | Example |
|---|-------|---------|
| 1 | Leading/trailing whitespace | `" Deluxe "` instead of `"Deluxe"` |
| 2 | Inconsistent text casing | `"online"`, `"ONLINE"`, `"Online"` in `booking_channel` or `hotel_name` |
| 3 | Missing categorical values | Null or blank `booking_channel`, `room_type`, or `guest_country` |
| 4 | Exact duplicate rows | Identical reservation rows repeated across ingestion |
| 5 | Invalid stay dates | `check_out_date <= check_in_date` (zero or negative stay duration) |
| 6 | Negative room rates | `room_rate < 0` or invalid negative monetary charges |
| 7 | Missing derived metrics | Missing `stay_nights` or null `discount_amount` |
| 8 | Unstandardized date/numeric formats | String representations requiring explicit type casting |

---

## 2. Rules by Layer

### Bronze: Preserve Raw Data
| Rule ID | Rule | Treatment |
|---------|------|-----------|
| BRZ-01 | Source values are kept strictly as-is | No trimming, casting, or filtering applied |
| BRZ-02 | Ingestion metadata added | `_ingest_timestamp`, `_source_file` captured via Auto Loader |
| BRZ-03 | Row count must match the source file (`1,316` rows) | Verified in `gold_data_quality` reconciliation |

### Silver: Standardize, Validate, Quarantine
| Rule ID | Dimension | Rule | Treatment | Action |
|---------|-----------|------|-----------|--------|
| SLV-01 | Standardization | Trim leading/trailing spaces on all text fields | `TRIM()` | Fix |
| SLV-02 | Standardization | Normalize casing across categorical columns (`hotel_name`, `city`, `room_type`, `booking_channel`, `booking_status`) | `INITCAP(TRIM(...))` | Fix |
| SLV-03 | Type validity | Cast dates (`check_in_date`, `check_out_date`) and numerics (`room_rate`, `discount_amount`, `total_amount`) | `CAST` / `TRY_CAST` | Fix |
| SLV-04 | Completeness | Impute missing categorical values and default discounts | `COALESCE(col, 'Unknown')`, `COALESCE(discount_amount, 0)` | Impute |
| SLV-05 | Derived Metrics | Compute stay duration in nights | `DATEDIFF(check_out_date, check_in_date)` | Enrich |
| SLV-06 | Business validity | Stay duration must be positive (`check_out_date > check_in_date`) | Declarative Expectation (`ON VIOLATION DROP ROW`) & route to quarantine | Quarantine |
| SLV-07 | Business validity | Room rate must be non-negative (`room_rate >= 0`) | Declarative Expectation (`ON VIOLATION DROP ROW`) & route to quarantine | Quarantine |
| SLV-08 | Duplicates | Exact duplicate booking rows | Deduplicate via `SELECT DISTINCT` | Exclude |

### Gold: Trusted Business Aggregations
| Rule ID | Rule | Treatment |
|---------|------|-----------|
| GLD-01 | Aggregations read strictly from `silver_bookings_clean` | Filter out quarantined/duplicate records |
| GLD-02 | Isolate cancelled bookings from net revenue calculations | Include cancellations in `gold_channel_summary` for cancellation rate tracking, exclude from net revenue totals |
| GLD-03 | End-to-end layer reconciliation | Verified via `gold_data_quality` materialized view |

---

## 3. Quarantine vs. Exclude

| | **Quarantine (`silver_bookings_rejected`)** | **Deduplicate / Exclude** |
|---|---|---|
| Meaning | Physically invalid record is filtered out of clean reporting and stored in a dedicated audit view with failure reasons | Exact duplicate record is removed so metrics are not double-counted |
| Use when | `check_out_date <= check_in_date` or `room_rate < 0` | Identical reservation rows appear multiple times |
| Visible in | `silver_bookings_rejected`, `gold_data_quality` | `gold_data_quality` duplicate count reconciliation |
| Reversible | Yes, raw data remains preserved in `bronze_hotel_bookings` | Yes, full refresh rebuilds deterministically from Bronze |

---

## 4. Pipeline Expectations (Lakeflow Declarative SQL)

Declarative data quality constraints enforced on `silver_bookings_clean`:

```sql
CONSTRAINT valid_stay_dates EXPECT (check_out_date > check_in_date) ON VIOLATION DROP ROW,
CONSTRAINT valid_room_rate  EXPECT (room_rate >= 0)                 ON VIOLATION DROP ROW
