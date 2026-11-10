"""Investigate quality flags without modifying source or converted files."""
from pathlib import Path
from decimal import Decimal, ROUND_HALF_UP
import argparse
import json
import pandas as pd

parser = argparse.ArgumentParser()
parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--output', type=Path)
args = parser.parse_args()
folder = args.project / 'data' / 'converted'
out = args.output or args.project / 'docs' / 'quality-investigation'
out.mkdir(parents=True, exist_ok=True)
t = pd.read_parquet(folder / 'transactions.parquet')
p = pd.read_parquet(folder / 'products.parquet')
if p.product_id.duplicated().any():
    raise ValueError('Product identifiers are not unique; investigate before joining.')
x = t.merge(p[['product_id', 'department', 'product_category', 'product_type']],
            on='product_id', how='left', validate='many_to_one', indicator=True)
assert len(x) == len(t)
x['department'] = x.department.fillna('(metadata unavailable)')
flags = {
    'zero_quantity': x.quantity.eq(0),
    'zero_sales': x.sales_value.eq(0),
    'zero_quantity_positive_sales': x.quantity.eq(0) & x.sales_value.gt(0),
    'positive_quantity_zero_sales': x.quantity.gt(0) & x.sales_value.eq(0),
    'both_zero': x.quantity.eq(0) & x.sales_value.eq(0),
    'quantity_above_100': x.quantity.gt(100),
    'missing_product_metadata': x['_merge'].eq('left_only'),
    'missing_timestamp': x.transaction_timestamp.isna(),
    'outside_2017': x.transaction_timestamp.notna() & ~x.transaction_timestamp.between(
        pd.Timestamp('2017-01-01'), pd.Timestamp('2018-01-01'), inclusive='left'),
}
report = {'notes': [
    'Flags overlap: their counts and sales must not be added together.',
    'Quantity above 100 is an investigation threshold, not an invalidity rule.',
    'Department patterns do not establish a quantity unit or correction factor.',
    'Sales summaries are rounded for display; no source values are changed.'
], 'flags': {}}
sample_cols = ['source_row_number', 'household_id', 'basket_id', 'product_id',
               'department', 'product_category', 'quantity', 'sales_value',
               'retail_disc', 'coupon_disc', 'coupon_match_disc', 'transaction_timestamp']
sample_cols = [c for c in sample_cols if c in x]
for label, mask in flags.items():
    rows = x.loc[mask]
    grouped = rows.groupby('department', observed=True).agg(
        rows=('product_id', 'size'), sales=('sales_value', 'sum'),
        minimum_quantity=('quantity', 'min'), maximum_quantity=('quantity', 'max'))
    grouped = grouped.sort_values('rows', ascending=False)
    report['flags'][label] = {'rows': len(rows),
        'sales_display_2dp': f'{rows.sales_value.sum():.2f}',
        'distinct_products': int(rows.product_id.nunique()),
        'by_department': grouped.reset_index().to_dict('records'),
        'examples': json.loads(rows.sort_values('quantity', ascending=False)
                              [sample_cols].head(10).to_json(orient='records', date_format='iso'))}

# Compare source float representations with a proposed decimal-cents policy.
report['money_review'] = {}
for col in ['sales_value', 'retail_disc', 'coupon_disc', 'coupon_match_disc']:
    values = [Decimal(str(v)) for v in t[col].dropna()]
    cents = [v.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP) for v in values]
    differences = [abs(a-b) for a,b in zip(values, cents)]
    report['money_review'][col] = {
        'sum_source_decimal_strings': str(sum(values, Decimal(0))),
        'sum_after_rounding_each_row_to_cents': str(sum(cents, Decimal(0))),
        'maximum_absolute_row_adjustment': str(max(differences, default=Decimal(0))),
        'rows_adjusted_more_than_0_000001': sum(v > Decimal('0.000001') for v in differences)}

# R Date columns may load as Python date objects rather than pandas datetimes.
report['date_columns'] = {}
for name, columns in {'campaign_descriptions': ['start_date', 'end_date'],
                      'coupon_redemptions': ['redemption_date']}.items():
    df = pd.read_parquet(folder / f'{name}.parquet')
    for col in columns:
        dates = pd.to_datetime(df[col], errors='coerce')
        report['date_columns'][f'{name}.{col}'] = {
            'source_dtype': str(df[col].dtype),
            'non_null_values_failing_date_conversion': int((df[col].notna() & dates.isna()).sum()),
            'minimum': str(dates.min()), 'maximum': str(dates.max())}

(out / 'quality-investigation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
lines = ['# Quality investigation', '', 'Source and converted files were not modified.', '']
lines += ['- ' + n for n in report['notes']]
lines += ['', '## Flag summary', '', '| Flag | Rows | Sales, 2 decimal places | Products |', '|---|---:|---:|---:|']
for name, item in report['flags'].items():
    lines.append(f"| {name} | {item['rows']:,} | {item['sales_display_2dp']} | {item['distinct_products']:,} |")
for name, item in report['flags'].items():
    lines += ['', f'## {name}: departments', '', '| Department | Rows | Sales | Min quantity | Max quantity |', '|---|---:|---:|---:|---:|']
    for row in item['by_department']:
        lines.append(f"| {row['department']} | {row['rows']:,} | {row['sales']:.2f} | {row['minimum_quantity']} | {row['maximum_quantity']} |")
lines += ['', '## Monetary precision review', '', '```json', json.dumps(report['money_review'], indent=2), '```',
          '', '## Additional date checks', '', '```json', json.dumps(report['date_columns'], indent=2), '```',
          '', 'Detailed examples with source row numbers are in quality-investigation.json.']
(out / 'quality-investigation.md').write_text('\n'.join(lines), encoding='utf-8')
print('\n'.join(lines[:19]))
print(f'\nReports saved to {out.resolve()}')
