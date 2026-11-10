-- ============================================================
-- DATA PROFILING AND QUALITY ASSESSMENT
-- Performed on staging (stg) tables after SSIS load
-- CompleteJourneyDW - IT3101 Data Warehousing & BI
-- ============================================================
USE CompleteJourneyDW;
GO

-- ============================================================
-- 1. COLUMN PROFILING: Row counts per staging table
-- ============================================================
PRINT '=== 1. ROW COUNTS PER STAGING TABLE ===';

SELECT 'stg.Transactions'       AS TableName, COUNT(*) AS [RowCount] FROM stg.Transactions
UNION ALL
SELECT 'stg.Products',           COUNT(*) FROM stg.Products
UNION ALL
SELECT 'stg.Demographics',       COUNT(*) FROM stg.Demographics
UNION ALL
SELECT 'stg.Campaigns',          COUNT(*) FROM stg.Campaigns
UNION ALL
SELECT 'stg.CampaignDescriptions', COUNT(*) FROM stg.CampaignDescriptions
UNION ALL
SELECT 'stg.Coupons',            COUNT(*) FROM stg.Coupons
UNION ALL
SELECT 'stg.CouponRedemptions',  COUNT(*) FROM stg.CouponRedemptions
ORDER BY TableName;
GO

-- ============================================================
-- 2. COLUMN PROFILING: Distinct values and NULL counts
-- ============================================================
PRINT '=== 2. TRANSACTION KEY FIELD PROFILING ===';

SELECT 
    COUNT(DISTINCT household_id)  AS DistinctHouseholds,
    COUNT(DISTINCT basket_id)     AS DistinctBaskets,
    COUNT(DISTINCT product_id)    AS DistinctProducts,
    COUNT(DISTINCT store_id)      AS DistinctStores,
    SUM(CASE WHEN household_id IS NULL THEN 1 ELSE 0 END) AS NullHouseholds,
    SUM(CASE WHEN basket_id IS NULL THEN 1 ELSE 0 END)    AS NullBaskets,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END)   AS NullProducts,
    SUM(CASE WHEN store_id IS NULL THEN 1 ELSE 0 END)     AS NullStores
FROM stg.Transactions;
GO

-- ============================================================
-- 3. STATISTICAL ANALYSIS: Transaction monetary measures
-- ============================================================
PRINT '=== 3. STATISTICAL ANALYSIS OF MONETARY FIELDS ===';

SELECT
    COUNT(*)                              AS TotalRows,
    CAST(SUM(CAST(ROUND(sales_value,2) AS DECIMAL(19,2))) AS DECIMAL(19,2))   AS TotalSalesValue,
    CAST(MIN(sales_value) AS DECIMAL(19,2))   AS MinSalesValue,
    CAST(MAX(sales_value) AS DECIMAL(19,2))   AS MaxSalesValue,
    CAST(AVG(sales_value) AS DECIMAL(19,2))   AS AvgSalesValue,
    CAST(SUM(CAST(ROUND(retail_disc,2) AS DECIMAL(19,2))) AS DECIMAL(19,2))   AS TotalRetailDiscount,
    CAST(SUM(CAST(ROUND(coupon_disc,2) AS DECIMAL(19,2))) AS DECIMAL(19,2))   AS TotalCouponDiscount,
    CAST(SUM(CAST(ROUND(coupon_match_disc,2) AS DECIMAL(19,2))) AS DECIMAL(19,2)) AS TotalCouponMatchDiscount
FROM stg.Transactions;
GO

-- ============================================================
-- 4. CROSS-TABLE PROFILING: Transaction-to-Product coverage
--    How many purchased products have no metadata?
-- ============================================================
PRINT '=== 4. CROSS-TABLE PROFILING: Missing Product Metadata ===';

SELECT 
    COUNT(DISTINCT t.product_id) AS ProductsWithNoMetadata,
    COUNT(*)                     AS AffectedPurchaseLines
FROM stg.Transactions t
LEFT JOIN stg.Products p ON t.product_id = p.product_id
WHERE p.product_id IS NULL;
GO

-- ============================================================
-- 5. CROSS-TABLE PROFILING: Household demographic coverage
--    How many purchasing households have demographic profiles?
-- ============================================================
PRINT '=== 5. CROSS-TABLE PROFILING: Demographic Coverage ===';

SELECT
    COUNT(DISTINCT t.household_id) AS TotalPurchasingHouseholds,
    COUNT(DISTINCT d.household_id) AS HouseholdsWithDemographics,
    COUNT(DISTINCT t.household_id) - COUNT(DISTINCT d.household_id) AS HouseholdsWithoutDemographics
FROM (SELECT DISTINCT household_id FROM stg.Transactions) t
LEFT JOIN stg.Demographics d ON t.household_id = d.household_id;
GO

-- ============================================================
-- 6. DATA RULE VALIDATION: Quantity anomalies
--    Checking for zero, negative, and unusually high quantities
-- ============================================================
PRINT '=== 6. DATA RULE VALIDATION: Quantity Anomalies ===';

SELECT
    SUM(CASE WHEN quantity = 0 THEN 1 ELSE 0 END)   AS ZeroQuantityRows,
    SUM(CASE WHEN quantity < 0 THEN 1 ELSE 0 END)   AS NegativeQuantityRows,
    SUM(CASE WHEN quantity > 100 THEN 1 ELSE 0 END) AS QuantityAbove100,
    SUM(CASE WHEN sales_value = 0 THEN 1 ELSE 0 END) AS ZeroSalesRows
FROM stg.Transactions;
GO

-- ============================================================
-- 7. DATA RULE VALIDATION: High-quantity department analysis
--    Which departments have the most extreme quantity values?
-- ============================================================
PRINT '=== 7. HIGH QUANTITY BY DEPARTMENT ===';

SELECT TOP 10
    ISNULL(p.department, 'NO METADATA') AS Department,
    COUNT(*)                            AS HighQuantityRows,
    CAST(SUM(t.sales_value) AS DECIMAL(19,2)) AS AssociatedSales,
    CAST(MIN(t.quantity) AS DECIMAL(12,2))    AS MinQty,
    CAST(MAX(t.quantity) AS DECIMAL(12,2))    AS MaxQty
FROM stg.Transactions t
LEFT JOIN stg.Products p ON t.product_id = p.product_id
WHERE t.quantity > 100
GROUP BY p.department
ORDER BY HighQuantityRows DESC;
GO

-- ============================================================
-- 8. DUPLICATE DETECTION: Check for duplicate purchase lines
-- ============================================================
PRINT '=== 8. DUPLICATE DETECTION ===';

WITH Pairs AS (
    SELECT basket_id,product_id,COUNT_BIG(*) AS Occurrences
    FROM stg.Transactions GROUP BY basket_id,product_id
)
SELECT SUM(Occurrences) AS TotalRows,COUNT_BIG(*) AS DistinctBasketProductPairs,
       SUM(Occurrences-1) AS PotentialDuplicates FROM Pairs;
GO

-- ============================================================
-- 9. CROSS-TABLE PROFILING: Campaign and coupon relationships
-- ============================================================
PRINT '=== 9. CAMPAIGN AND COUPON RELATIONSHIP CHECKS ===';

-- Check all campaign IDs in campaigns table exist in descriptions
SELECT 
    COUNT(DISTINCT c.campaign_id) AS CampaignsWithDescriptions,
    (SELECT COUNT(DISTINCT campaign_id) FROM stg.Campaigns) AS TotalCampaignRecipientIDs,
    (SELECT COUNT(DISTINCT campaign_id) FROM stg.CampaignDescriptions) AS TotalCampaignDescriptions
FROM stg.Campaigns c
INNER JOIN stg.CampaignDescriptions cd ON c.campaign_id = cd.campaign_id;
GO

-- ============================================================
-- 10. PATTERN DISCOVERY: Product category distribution
-- ============================================================
PRINT '=== 10. PRODUCT DEPARTMENT DISTRIBUTION ===';

SELECT 
    ISNULL(department, 'NULL') AS Department,
    COUNT(*)                   AS ProductCount,
    COUNT(DISTINCT product_category) AS DistinctCategories
FROM stg.Products
GROUP BY department
ORDER BY ProductCount DESC;
GO

PRINT '=== DATA PROFILING COMPLETE ===';
GO

-- Additional anti-join checks: parent duplicates cannot multiply these counts.
SELECT 'Coupons without campaign descriptions' AS CheckName,COUNT_BIG(*) AS UnmatchedRows FROM stg.Coupons c
WHERE NOT EXISTS(SELECT 1 FROM stg.CampaignDescriptions d WHERE d.campaign_id=c.campaign_id)
UNION ALL SELECT 'Coupons without product metadata',COUNT_BIG(*) FROM stg.Coupons c
WHERE NOT EXISTS(SELECT 1 FROM stg.Products p WHERE p.product_id=c.product_id)
UNION ALL SELECT 'Redemptions without campaign recipients',COUNT_BIG(*) FROM stg.CouponRedemptions r
WHERE NOT EXISTS(SELECT 1 FROM stg.Campaigns c WHERE c.household_id=r.household_id AND c.campaign_id=r.campaign_id)
UNION ALL SELECT 'Redemptions without eligible coupon pairs',COUNT_BIG(*) FROM stg.CouponRedemptions r
WHERE NOT EXISTS(SELECT 1 FROM stg.Coupons c WHERE c.campaign_id=r.campaign_id AND c.coupon_upc=r.coupon_upc);
GO
