from pathlib import Path
import json

import pandas as pd
import pyreadr

PROJECT = Path(__file__).resolve().parents[1]
RAW = PROJECT / "data" / "raw"
CONVERTED = PROJECT / "data" / "converted"
DOCS = PROJECT / "docs"

CONVERTED.mkdir(parents=True, exist_ok=True)
DOCS.mkdir(parents=True, exist_ok=True)

FILES = {
    "transactions.rds": 1469307,
    "products.rda": 92331,
    "demographics.rda": 801,
    "campaigns.rda": 6589,
    "campaign_descriptions.rda": 27,
    "coupons.rda": 116204,
    "coupon_redemptions.rda": 2102,
}

# Stop before conversion if any required file is absent.
missing = [name for name in FILES if not (RAW / name).is_file()]
if missing:
    raise FileNotFoundError(f"Missing source files: {missing}")

results = []

for filename, expected_rows in FILES.items():
    source = RAW / filename
    objects = pyreadr.read_r(str(source))

    if len(objects) != 1:
        raise ValueError(
            f"{filename}: expected one data object, found {len(objects)}"
        )

    original = next(iter(objects.values()))

    if not isinstance(original, pd.DataFrame):
        raise TypeError(f"{filename}: source object is not a table")

    if len(original) != expected_rows:
        raise ValueError(f"{filename}: expected {expected_rows:,} rows, found {len(original):,}. Output was not replaced.")

    data = original.copy()
    timestamp_changes = {}

    # Standardise timestamp storage for the Parquet round trip.
    # Dates, times and missing values are preserved.
    for column in data.select_dtypes(
        include=["datetime", "datetimetz"]
    ).columns:
        previous_dtype = str(data[column].dtype)
        data[column] = data[column].dt.as_unit("ns", round_ok=False)

        if previous_dtype != str(data[column].dtype):
            timestamp_changes[column] = {
                "from": previous_dtype,
                "to": str(data[column].dtype),
            }

    # Add traceability back to each original source row.
    data["source_file"] = filename
    data["source_row_number"] = range(1, len(data) + 1)

    output = CONVERTED / f"{source.stem}.parquet"
    pending = output.with_suffix(".parquet.pending")
    data.to_parquet(pending, engine="pyarrow", index=False)

    # Verify exact values and types after saving and reopening.
    restored = pd.read_parquet(pending, engine="pyarrow")

    pd.testing.assert_frame_equal(
        data.reset_index(drop=True),
        restored.reset_index(drop=True),
        check_dtype=True,
        check_exact=True,
    )

    pending.replace(output)

    matches_expected = len(original) == expected_rows

    results.append({
        "file": filename,
        "actual_rows": len(original),
        "expected_rows": expected_rows,
        "matches_expected": matches_expected,
        "source_columns": list(original.columns),
        "source_dtypes": {
            column: str(dtype)
            for column, dtype in original.dtypes.items()
        },
        "converted_dtypes": {
            column: str(dtype)
            for column, dtype in data.dtypes.items()
        },
        "timestamp_storage_changes": timestamp_changes,
        "missing_values": {
            column: int(count)
            for column, count in original.isna().sum().items()
        },
        "parquet_round_trip": "passed",
    })

    status = "MATCH" if matches_expected else "REVIEW COUNT"
    print(
        f"{filename}: {len(original):,} rows | "
        f"{status} | verified"
    )

report = DOCS / "conversion-checks.json"
report.write_text(
    json.dumps(results, indent=2),
    encoding="utf-8",
)

print("\nFinished. Original files were not modified.")
print(f"Validation report: {report}")

if not all(result["matches_expected"] for result in results):
    raise ValueError(
        "Conversion checks passed, but some row counts differ "
        "from expectations. Review conversion-checks.json."
    )

print("All seven files passed conversion and row-count checks.")