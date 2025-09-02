# 📌 PostgreSQL Logs Streaming to Lakehouse (UAT)

## **Destination**
- **Catalog:** `vitality_lakehouse_uat`  
- **Schema:** `pg_archive_sync`  
- **Tables:**  
  - **Primary server:** `primary_postgresql_logs_uat`  
  - **Replica server:** `replica_postgresql_logs_uat`  

---

## **Streaming Library**
- **Module:** `azure_blob_streaming.py`  
- **Class:** `AppendBlobTailer`  
- **Purpose:**  
  - Stream NDJSON logs from Azure Append Blob Storage  
  - Handle offset checkpointing via state file  
  - Support cold start options (`earliest`, `latest`)  
  - Parse and batch JSON records for downstream processing  

---

## **Disk Monitoring**
- **Module:** `space_monitoring.py`  
- **Class:** `DiskSpaceMonitor`  
- **Purpose:**  
  - Ensure minimum free disk space during ingestion  
  - Automatically clean up expired files (>1h old) in `/tmp`  
  - Integrates with Spark cache cleanup and Python garbage collection  

---

## **Pipeline Orchestration**
- **Module:** `main.py`  
- **Responsibilities:**  
  1. Initialize `AppendBlobTailer` to stream PostgreSQL WAL logs from Blob.  
  2. Continuously fetch and parse records.  
  3. Commit offsets (`.offset.json`) for fault-tolerant recovery.  
  4. Integrate with `DiskSpaceMonitor` to prevent disk exhaustion.  
  5. Write processed logs into **Lakehouse tables**:
     - `pg_archive_sync.primary_postgresql_logs_uat`
     - `pg_archive_sync.replica_postgresql_logs_uat`

---

## **High-Level Flow**
1. **Source:** Azure Append Blob (NDJSON logs)  
2. **Ingestion:** `AppendBlobTailer.read_next()`  
3. **Processing:** Transform / validate JSON records  
4. **Storage:** Write to `vitality_lakehouse_uat.pg_archive_sync` tables  
5. **Monitoring:** `DiskSpaceMonitor.ensure_space()` during pipeline run  

---

## **Future Enhancements**
- Add structured logging (Databricks / Azure Monitor integration).  
- Implement retry/backoff strategy for blob reading.  
- Support streaming into Delta Lake format with schema enforcement.  
- Automate orchestration with Airflow/Databricks Jobs.  
