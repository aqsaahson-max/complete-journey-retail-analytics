"""Export all seven verified Parquet tables; verify CSVs before publication."""
from pathlib import Path
import argparse, datetime, hashlib, json, os
import pandas as pd

parser=argparse.ArgumentParser()
parser.add_argument('--project',type=Path,default=Path(__file__).resolve().parents[1])
args=parser.parse_args()
project=args.project
converted=project/'data/converted';target=project/'data/csv_staging'
names=['transactions','products','demographics','campaigns','campaign_descriptions','coupons','coupon_redemptions']
missing=[n for n in names if not (converted/f'{n}.parquet').is_file()]
if missing:raise FileNotFoundError(f'Missing required Parquet inputs: {missing}. No CSV files were replaced.')
target.mkdir(parents=True,exist_ok=True)
pending=[];manifest={}
try:
    for name in names:
        source=converted/f'{name}.parquet'
        original=pd.read_parquet(source).drop(columns=['source_file','source_row_number'],errors='ignore')
        temp=target/f'{name}.csv.pending'
        pending.append((temp,target/f'{name}.csv'))
        original.to_csv(temp,index=False,encoding='utf-8')
        types={c:original[c].dtype if pd.api.types.is_numeric_dtype(original[c]) else 'string' for c in original}
        restored=pd.read_csv(temp,dtype=types,keep_default_na=False,na_values=[''],float_precision='round_trip',encoding='utf-8')
        if list(restored)!=list(original) or len(restored)!=len(original):raise ValueError(f'{name}: CSV shape changed')
        for col in original:
            left=original[col].reset_index(drop=True);right=restored[col]
            if not left.isna().equals(right.isna()):raise ValueError(f'{name}.{col}: missing values changed')
            if pd.api.types.is_numeric_dtype(left):pass
            elif pd.api.types.is_datetime64_any_dtype(left):right=pd.to_datetime(right)
            elif len(left.dropna()) and isinstance(left.dropna().iloc[0],datetime.date):right=pd.to_datetime(right).dt.date
            else:left=left.astype('string');right=right.astype('string')
            pd.testing.assert_series_equal(left,right,check_names=False,check_dtype=False,check_exact=True)
        manifest[name]={'rows':len(original),'columns':list(original),'parquet_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'csv_sha256':hashlib.sha256(temp.read_bytes()).hexdigest(),'csv_readback':'passed'}
        print(f'{name}: {len(original):,} rows; all CSV values verified')
    # Publish only after every dataset passed; each individual replacement is atomic.
    for temp,final in pending:os.replace(temp,final)
    docs=project/'docs';docs.mkdir(exist_ok=True)
    (docs/'csv-export-checks.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
except Exception:
    for temp,_ in pending:temp.unlink(missing_ok=True)
    raise
print('All seven CSV files verified and published. Row provenance remains in Parquet.')
