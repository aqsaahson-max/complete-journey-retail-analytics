# Setup and execution order

## Requirements
Windows, Python with the packages in `requirements.txt`, SQL Server, SQL Server Management Studio, Visual Studio with SQL Server Integration Services Projects, and Power BI Desktop. The SSIS database connection uses the Microsoft OLE DB Driver for SQL Server (`MSOLEDBSQL.1`); install a compatible driver or configure the connection for your installed provider. The dependency ranges are declared requirements, not a lockfile from the original execution environment.

## 1. Prepare the files
Obtain the seven source files described in [the dataset guide](../data/README.md). From the project root:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe etl/01_convert_sources.py
.\.venv\Scripts\python.exe etl/02_profile_sources.py
.\.venv\Scripts\python.exe etl/03_investigate_quality.py
.\.venv\Scripts\python.exe etl/04_export_to_csv.py
```
Inspect the generated profiling and quality reports. The aggregate original run manifests are retained in `evidence/`; new runs write their reports into `docs/`.

## 2. Create a dedicated database
Run `sql/create_star_schema.sql` in SSMS on your chosen SQL Server. It creates `CompleteJourneyDW` and the staging, warehouse and audit structures. Review the script before execution; database creation is an initial-setup step, not a migration for an existing database.

## 3. Configure and execute SSIS
Open `ssis/CompleteJourneyETL/CompleteJourneyETL.dtproj` in Visual Studio with the SSIS extension. The showcase copy uses `localhost` and `C:\CompleteJourney\data\csv_staging` as example connection settings. Edit the SQL connection and all seven flat-file connection managers for your machine. Use Windows authentication or configure your own credentials locally; do not commit credentials.

Confirm that the Reset Staging task targets the intended project database. It clears staging data. Then execute the package, inspect the task results and verify staging row counts using `sql/data_profiling.sql`. SSIS performs the staging import; the warehouse SQL load is a subsequent step.

## 4. Load and validate the warehouse
Before running `sql/load_star_schema.sql`, compare the SHA-256 hash of your raw `transactions.rds` with its declared `@SourceHash`. Use `Get-FileHash -Algorithm SHA256 data/raw/transactions.rds`. The script records a fixed snapshot label and hash; it does not calculate the source-file hash from SQL staging. If using a different source snapshot, review all expectations and update the metadata deliberately instead of bypassing validation.

Run `sql/load_star_schema.sql`, then `sql/verify_warehouse.sql`. The loader replaces the fact table after its preflight checks; use only the intended project database. Review the audit and reconciliation outputs. Run `sql/create_data_marts.sql` and `sql/analytical_queries.sql` for the category-performance view and example analyses.

## 5. Rebuild or reconnect Power BI
The data-bearing PBIX is not included. Use [the dashboard guide](../powerbi/README.md), warehouse model image and measure definitions to reproduce the report. Import the warehouse tables from your SQL Server, configure the four active dimension-to-fact relationships and create the visuals. The repository is not a one-click dashboard installer.

## Verification boundary
Source code and retained outputs document the original project. Preparing this showcase package did not rerun SQL Server, SSIS or Power BI. The sanitized SSIS connections need local configuration and execution testing. Code syntax and document checks are distinct from an end-to-end rerun.

The supplied SSIS project targets SQL Server 2025. Match that target with your installed SSIS tooling, or deliberately retarget and validate it for your server version before execution.
