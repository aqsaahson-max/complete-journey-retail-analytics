USE CompleteJourneyDW;
GO
SET XACT_ABORT ON;
BEGIN TRANSACTION;
TRUNCATE TABLE stg.Transactions;
TRUNCATE TABLE stg.Products;
TRUNCATE TABLE stg.Demographics;
TRUNCATE TABLE stg.Campaigns;
TRUNCATE TABLE stg.CampaignDescriptions;
TRUNCATE TABLE stg.Coupons;
TRUNCATE TABLE stg.CouponRedemptions;
COMMIT;
GO
-- Run BEFORE SSIS. Do not reset staging after SSIS finishes.
