# PostgreSQL Logs Streaming Pipeline - Step Design

## **1. Initialization**
- **Inputs:**
  - `blob_url`: Azure Blob URL containing NDJSON log files.  
  - `state_file`: Path to store current offset & etag for resuming.  
  - `cold_start`: Starting point if no state file exists (`earliest` or `latest`).  
  - `min_free_gb`: Minimum free disk threshold.  
- **Components Initialized:**
  - `AppendBlobTailer` (from `azure_blob_streaming.py`)  
  - `DiskSpaceMonitor` (from `space_monitoring.py`)  

---

## **2. Disk Monitoring Step**
- `DiskSpaceMonitor.ensure_space()`:
  1. Check free disk space.  
  2. If below threshold:
     - Clear Spark cache (if available).  
     - Trigger Python garbage collection.  
     - Delete files older than 1h in `/tmp`.  
  3. Re-check free space.  
  4. If still below threshold → raise error.  

---

## **3. Blob Reading Step**
- `AppendBlobTailer.read_next()`:
  1. Resolve starting offset:
     - If state file exists → load from it.  
     - Otherwise → use `cold_start`.  
  2. Download a chunk of blob data (`chunk_bytes`).  
  3. Decode bytes → UTF-8 string.  
  4. Split into lines, discard incomplete last line.  
  5. Parse lines into JSON records.  
  6. Return `(records, next_offset, meta)`.

---

## **4. Processing Step**
- **Process records (`recs`)**:  
  - Validate JSON structure.  
  - Transform if needed.  
  - Prepare for storage (map fields to target schema).  

---

## **5. Commit Progress**
- `AppendBlobTailer.commit(next_offset, etag)`:
  1. Update internal pointer.  
  2. Save state (offset + etag) into JSON file.  
  3. Enables recovery in case of restart/failure.  

---

## **6. Storage Step**
- Write processed records into Lakehouse:  
  - Catalog: `vitality_lakehouse_uat`  
  - Schema: `pg_archive_sync`  
  - Tables:  
    - `primary_postgresql_logs_uat`  
    - `replica_postgresql_logs_uat`  

---

## **7. Orchestration Loop**
- Repeat steps:
  1. Monitor disk space.  
  2. Read new records from blob.  
  3. Process records.  
  4. Write to Lakehouse tables.  
  5. Commit offset.  
  6. Sleep briefly, then continue.  

---

## **8. Error Handling**
- Blob read errors (invalid range, modification) → retry download.  
- JSON parse errors → skip invalid line.  
- Disk cleanup errors → log warning, continue.  
- Critical errors (disk full after cleanup) → stop pipeline.  

---

## **High-Level Flow Diagram (Text Version)**

```
[Start]
   │
   ▼
[Init Tailer + Monitor]
   │
   ▼
[Check Disk Space]───No Space───> [Clean Old Files]
   │
   ▼
[Read Blob Chunk]
   │
   ▼
[Parse JSON Records]
   │
   ▼
[Process + Store in Lakehouse]
   │
   ▼
[Commit Offset + Save State]
   │
   ▼
[Wait / Loop Back to Read Next]
```
