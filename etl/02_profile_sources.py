"""Read-only source profiling. Run from etl, or pass --project and --output."""
from pathlib import Path
from decimal import Decimal
import argparse
import json
import pandas as pd

parser = argparse.ArgumentParser()
parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--output', type=Path)
args = parser.parse_args()
out = args.output or args.project / 'docs' / 'profiling'
out.mkdir(parents=True, exist_ok=True)
names = ['transactions', 'products', 'demographics', 'campaigns',
         'campaign_descriptions', 'coupons', 'coupon_redemptions']
tables = {}
report = {'tables': {}, 'candidate_keys': [], 'relationships': []}
for name in names:
    df = pd.read_parquet(args.project / 'data' / 'converted' / f'{name}.parquet')
    df = df.drop(columns=['source_file', 'source_row_number'], errors='ignore')
    tables[name] = df
    columns = {}
    for col in df:
        s = df[col]
        item = {'dtype': str(s.dtype), 'nulls': int(s.isna().sum()),
                'distinct_non_null': int(s.nunique())}
        if pd.api.types.is_numeric_dtype(s):
            item.update(minimum=str(s.min()), maximum=str(s.max()),
                        zero_rows=int(s.eq(0).sum()), negative_rows=int(s.lt(0).sum()))
        if pd.api.types.is_datetime64_any_dtype(s):
            item.update(minimum=str(s.min()), maximum=str(s.max()))
        if pd.api.types.is_string_dtype(s) or isinstance(s.dtype, pd.CategoricalDtype):
            item['blank_strings'] = int(s.astype('string').str.strip().eq('').sum())
        columns[col] = item
    report['tables'][name] = {'rows': len(df),
        'duplicate_excess_rows': int(df.duplicated().sum()),
        'rows_in_duplicate_groups': int(df.duplicated(keep=False).sum()),
        'columns': columns}
    print(f'Profiled {name}: {len(df):,} rows')

def key(name, cols):
    df = tables[name]
    report['candidate_keys'].append({'table': name, 'columns': cols,
        'null_key_rows': int(df[cols].isna().any(axis=1).sum()),
        'duplicate_excess_rows': int(df.duplicated(cols).sum())})

for name, cols in [('transactions', ['basket_id', 'product_id']),
    ('products', ['product_id']), ('demographics', ['household_id']),
    ('campaign_descriptions', ['campaign_id']),
    ('campaigns', ['household_id', 'campaign_id']),
    ('coupons', ['campaign_id', 'coupon_upc', 'product_id']),
    ('coupon_redemptions', ['household_id', 'campaign_id', 'coupon_upc', 'redemption_date'])]:
    key(name, cols)

def relation(child, parent, cols, label):
    c, p = tables[child][cols], tables[parent][cols]
    nulls = c.isna().any(axis=1)
    checked = c.loc[~nulls].merge(p.dropna().drop_duplicates(), on=cols,
                                 how='left', indicator=True)
    unmatched = checked.loc[checked['_merge'].eq('left_only'), cols]
    report['relationships'].append({'check': label,
        'child_rows': len(c), 'null_key_rows': int(nulls.sum()),
        'unmatched_rows': len(unmatched),
        'unmatched_distinct_keys': len(unmatched.drop_duplicates())})

relation('transactions', 'products', ['product_id'], 'Purchases to product metadata')
relation('transactions', 'demographics', ['household_id'], 'Purchases to optional demographics')
for child in ['campaigns', 'coupons', 'coupon_redemptions']:
    relation(child, 'campaign_descriptions', ['campaign_id'], f'{child} to campaign descriptions')
relation('coupons', 'products', ['product_id'], 'Coupon eligibility to products')
relation('coupon_redemptions', 'campaigns', ['household_id', 'campaign_id'], 'Redemptions to campaign recipients')
relation('coupon_redemptions', 'coupons', ['campaign_id', 'coupon_upc'], 'Redemptions to eligible campaign-coupon pairs')

t = tables['transactions']
money = ['sales_value', 'retail_disc', 'coupon_disc', 'coupon_match_disc']
report['baseline'] = {
    'purchase_rows': len(t), 'households': int(t.household_id.nunique()),
    'baskets': int(t.basket_id.nunique()), 'stores': int(t.store_id.nunique()),
    'quantity_total': str(t.quantity.sum()),
    'nonpositive_quantity_rows': int(t.quantity.le(0).sum()),
    'first_timestamp': str(t.transaction_timestamp.min()),
    'last_timestamp': str(t.transaction_timestamp.max()),
    'monetary_totals_decimal_from_source_strings': {
        col: str(sum((Decimal(str(v)) for v in t[col].dropna()), Decimal(0))) for col in money},
    'monetary_quantiles': {col: {str(k): float(v) for k, v in
        t[col].quantile([0, .5, .95, .99, 1]).items()} for col in money},
    'baskets_with_multiple_households': int(t.groupby('basket_id').household_id.nunique().gt(1).sum()),
    'baskets_with_multiple_stores': int(t.groupby('basket_id').store_id.nunique().gt(1).sum()),
}
d = tables['campaign_descriptions']
report['campaign_checks'] = {'end_before_start_rows': int(d.end_date.lt(d.start_date).sum())}
if not d.campaign_id.duplicated().any():
    r = tables['coupon_redemptions'].merge(d, on='campaign_id', how='left', validate='many_to_one')
    known = r.start_date.notna() & r.end_date.notna() & r.redemption_date.notna()
    outside = r.redemption_date.lt(r.start_date) | r.redemption_date.gt(r.end_date)
    report['campaign_checks']['redemptions_outside_campaign_dates'] = int((known & outside).sum())
    report['campaign_checks']['redemptions_with_uncheckable_dates'] = int((~known).sum())

(out / 'source-profile.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
lines = ['# Source profiling results', '',
    'Read-only inspection of converted files. No records were cleaned or removed.', '',
    'Duplicate counts exclude source-tracking columns. Excess rows count occurrences after the first.', '',
    '## Table summary', '', '| Table | Rows | Excess duplicate rows |', '|---|---:|---:|']
for name, info in report['tables'].items():
    lines.append(f"| {name} | {info['rows']:,} | {info['duplicate_excess_rows']:,} |")
lines += ['', '## Candidate keys', '', 'These are observed uniqueness tests, not proof of business identity.', '',
          '| Table / columns | Null key rows | Excess duplicates |', '|---|---:|---:|']
for k in report['candidate_keys']:
    lines.append(f"| {k['table']}: {', '.join(k['columns'])} | {k['null_key_rows']:,} | {k['duplicate_excess_rows']:,} |")
lines += ['', '## Relationships', '', '| Check | Null key rows | Unmatched rows | Unmatched distinct keys |', '|---|---:|---:|---:|']
for r in report['relationships']:
    lines.append(f"| {r['check']} | {r['null_key_rows']:,} | {r['unmatched_rows']:,} | {r['unmatched_distinct_keys']:,} |")
lines += ['', 'Optional demographics coverage is not a requirement for a valid purchase.', '',
          '## Baseline and campaign checks', '', '```json',
          json.dumps({'baseline': report['baseline'], 'campaign_checks': report['campaign_checks']}, indent=2), '```', '',
          '## Column details', '']
for name, info in report['tables'].items():
    lines += [f'### {name}', '', '| Column | Type | Nulls | Distinct | Blank strings | Min | Max | Zero | Negative |',
              '|---|---|---:|---:|---:|---|---|---:|---:|']
    for col, c in info['columns'].items():
        lines.append('| ' + ' | '.join(str(v) for v in [col, c['dtype'], c['nulls'], c['distinct_non_null'],
            c.get('blank_strings', ''), c.get('minimum', ''), c.get('maximum', ''),
            c.get('zero_rows', ''), c.get('negative_rows', '')]) + ' |')
    lines.append('')
lines += ['## Interpretation limits', '',
    '- Missing metadata should not automatically exclude purchases.',
    '- Duplicate eligibility records need a documented bridge-table rule.',
    '- Nonpositive quantities and large amounts require investigation; this report does not label them errors.',
    '- Coupon eligibility cannot identify the product actually redeemed.',
    '- Sales values are source receipts; discount totals are reported separately and not subtracted again.',
    '- No campaign effect or return on investment is established by these checks.']
(out / 'source-profile.md').write_text('\n'.join(lines), encoding='utf-8')
print(f'Reports saved to {out.resolve()}')
