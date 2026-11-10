# Dataset and source files

Source: 84.51° Complete Journey, distributed through the completejourney project.
- [Dataset documentation](https://bradleyboehmke.github.io/completejourney/articles/completejourney.html)
- [Packaged source tables](https://github.com/bradleyboehmke/completejourney/tree/master/data)

Obtain the full transactions dataset described by the source documentation, not a small example sample. Review the original dataset's terms before downloading or redistributing it. No source records are included in this repository.

Place the following files in `data/raw/`:

| File | Required rows in the project snapshot |
|---|---:|
| transactions.rds | 1,469,307 |
| products.rda | 92,331 |
| demographics.rda | 801 |
| campaigns.rda | 6,589 |
| campaign_descriptions.rda | 27 |
| coupons.rda | 116,204 |
| coupon_redemptions.rda | 2,102 |

The conversion script deliberately rejects different row counts. This is a snapshot-specific academic pipeline, not a general-purpose importer. Conversion creates `data/converted/`; CSV export creates `data/csv_staging/`. Generated row-level profiling reports should remain local.
