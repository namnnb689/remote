# PG‑Audit Log Ingestion

**Owner**: Data Platform – Tian Nguyen
**Audience**: Senior Data/DE, Ops, SRE
**Last updated**: \<dd/mm/yyyy>

---

## 1) Objective

Ingest **PostgreSQL Audit Logs** (primary & replica) into the Lakehouse for security analytics, change tracking, and compliance. This document describes **architecture**, **schema standards**, **configuration**, and **orchestration**.

---

## 2) Destination

* **Catalog**: `vitality_lakehouse_uat`
* **Schema**: `pg_archive_sync`
* **Tables**:

  * **Primary server** → `primary_postgresql_logs_uat`
  * **Replica server** → `replica_postgresql_logs_uat`

### 2.1) Standard Schema (applies to both tables)

| Column        | Type                | Description                                        |
| ------------- | ------------------- | -------------------------------------------------- |
| `event_time`  | TIMESTAMP           | Time when the audit event was recorded             |
| `db_name`     | STRING              | Target database                                    |
| `user_name`   | STRING              | Executing user                                     |
| `client_addr` | STRING              | Client IP/host                                     |
| `session_id`  | STRING              | Session/Backend PID                                |
| `command_tag` | STRING              | Command type (SELECT/UPDATE/…)                     |
| `object_type` | STRING              | Table/Schema/Function…                             |
| `object_name` | STRING              | Object name                                        |
| `statement`   | STRING              | Original SQL statement (normalized)                |
| `audit_class` | STRING              | pgaudit class (READ, WRITE, ROLE, DDL…)            |
| `result`      | STRING              | SUCCESS/FAILURE                                    |
| `error_code`  | STRING              | Error code (if any)                                |
| `extra`       | MAP\<STRING,STRING> | Extra key/values (db\_user, app\_name, relay\_id…) |
| `ingest_ts`   | TIMESTAMP           | Ingestion timestamp                                |
| `src`         | STRING              | `primary` or `replica`                             |
| `raw`         | STRING              | Original raw log line                              |

> Note: if the team uses **Delta/Iceberg**, standardize `ingest_ts` as a **partition column** (e.g. by day) for query performance.

---

## 3) High-Level Architecture

```
+------------------+       tail/stream       +-------------------+
| PG Primary       |  -------------------->  | Ingestion Worker  |---+
| (pgaudit/csvlog) |                         | (python_utils)    |   |
+------------------+                          +-------------------+   |
                                                                      v
+------------------+       tail/stream       +-------------------+   Lakehouse
| PG Replica       |  -------------------->  | Ingestion Worker  |---->  Catalog: vitality_lakehouse_uat
| (pgaudit/csvlog) |                         | (python_utils)    |        Schema: pg_archive_sync
+------------------+                          +-------------------+        Tables: primary_*, replica_*
                                                                      ^
                                                                      |
                                                         Monitoring/Alerting (Ops)
```

* **Input**: PostgreSQL `pgaudit`/`csvlog` files (or log sink/Blob/CloudWatch depending on environment).
* **Processing**: normalize using **python\_utils** (team repo), parse → enrich → validate.
* **Sink**: Lakehouse (Delta/Iceberg/Parquet) with the two destination tables listed above.

---

## 4) Streaming Library

* **Language**: Python 3.x
* **Streaming options**:

  * `asyncio + watchdog` (file tailing), or
  * `PySpark Structured Streaming` if logs are pushed to object storage.
* **Shared Utilities**: leverage **`python_utils`** (logging, config, blob helpers, retry, time handling…).

> Repo `python_utils`: reuse modules for **config**, **logging**, **io/storage**, **retry/time**. Custom parser/writer can be added under an `ingestion_utils` module.

---

## 5) Pipeline Orchestration

* **Option A (simple)**: Run as long‑lived services using `systemd`/`supervisor` (separate workers for primary and replica).
* **Option B (Data Engineering standard)**: **Airflow DAG** to deploy workers, rotate checkpoints, compact and optimize tables.
* **Option C (Databricks/Cloud)**: Use **Workflows/Jobs** for Structured Streaming + Auto Loader.
