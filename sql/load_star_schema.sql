USE CompleteJourneyDW;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @LoadRunKey INT, @SnapshotKey INT, @LockResult INT;
DECLARE @SnapshotLabel VARCHAR(200)='completejourney_2026-09-29_full_refresh';
DECLARE @SourceHash VARCHAR(64)='1fa0700033f1e5d9bb6b09e2be063d8d68474d346e95c50f2833e09d083e0007';
-- This hash identifies the verified raw transaction file, not each SQL row.
EXEC @LockResult=sys.sp_getapplock @Resource='CompleteJourneyDW_FullRefresh',
    @LockMode='Exclusive',@LockOwner='Session',@LockTimeout=0;
IF @LockResult<0 THROW 51000,'Another warehouse refresh is running.',1;
INSERT audit.LoadRun(Status,Notes) VALUES('RUNNING','Validated full replacement; batch lineage, not original row-level lineage.');
SET @LoadRunKey=SCOPE_IDENTITY();
BEGIN TRY
    BEGIN TRANSACTION;
    -- Staging must remain stable throughout preflight and load.
    DECLARE @Counts TABLE(Name VARCHAR(50),Expected BIGINT,Actual BIGINT);
    INSERT @Counts VALUES
    ('Transactions',1469307,(SELECT COUNT_BIG(*) FROM stg.Transactions WITH(TABLOCKX,HOLDLOCK))),
    ('Products',92331,(SELECT COUNT_BIG(*) FROM stg.Products WITH(TABLOCKX,HOLDLOCK))),
    ('Demographics',801,(SELECT COUNT_BIG(*) FROM stg.Demographics WITH(TABLOCKX,HOLDLOCK))),
    ('Campaigns',6589,(SELECT COUNT_BIG(*) FROM stg.Campaigns WITH(TABLOCKX,HOLDLOCK))),
    ('CampaignDescriptions',27,(SELECT COUNT_BIG(*) FROM stg.CampaignDescriptions WITH(TABLOCKX,HOLDLOCK))),
    ('Coupons',116204,(SELECT COUNT_BIG(*) FROM stg.Coupons WITH(TABLOCKX,HOLDLOCK))),
    ('CouponRedemptions',2102,(SELECT COUNT_BIG(*) FROM stg.CouponRedemptions WITH(TABLOCKX,HOLDLOCK)));
    IF EXISTS(SELECT 1 FROM @Counts WHERE Expected<>Actual)
        THROW 51001,'Staging counts differ from the verified release. Refresh all seven staging tables first.',1;
    IF EXISTS(SELECT 1 FROM stg.Transactions WHERE NULLIF(LTRIM(RTRIM(household_id)),'') IS NULL
        OR NULLIF(LTRIM(RTRIM(product_id)),'') IS NULL OR NULLIF(LTRIM(RTRIM(store_id)),'') IS NULL
        OR NULLIF(LTRIM(RTRIM(basket_id)),'') IS NULL OR transaction_timestamp IS NULL
        OR quantity IS NULL OR sales_value IS NULL OR retail_disc IS NULL OR coupon_disc IS NULL OR coupon_match_disc IS NULL)
        THROW 51002,'Mandatory transaction values are missing. No facts were replaced.',1;
    IF EXISTS(SELECT 1 FROM stg.Products GROUP BY product_id HAVING COUNT(*)>1)
       OR EXISTS(SELECT 1 FROM stg.Demographics GROUP BY household_id HAVING COUNT(*)>1)
       OR EXISTS(SELECT 1 FROM stg.CampaignDescriptions GROUP BY campaign_id HAVING COUNT(*)>1)
       OR EXISTS(SELECT 1 FROM stg.Transactions GROUP BY basket_id,product_id HAVING COUNT(*)>1)
        THROW 51003,'Duplicate source keys would multiply records. No facts were replaced.',1;
    IF EXISTS(SELECT 1 FROM stg.Transactions WHERE CAST(transaction_timestamp AS DATE)<'2016-01-01'
        OR CAST(transaction_timestamp AS DATE)>'2018-12-31')
        THROW 51004,'Transaction dates exceed the configured calendar.',1;
    IF NOT EXISTS(SELECT 1 FROM audit.SourceSnapshot WHERE SnapshotLabel=@SnapshotLabel)
        INSERT audit.SourceSnapshot(SnapshotLabel,SourceFileHash) VALUES(@SnapshotLabel,@SourceHash);
    SELECT @SnapshotKey=SourceSnapshotKey FROM audit.SourceSnapshot WHERE SnapshotLabel=@SnapshotLabel;
    IF EXISTS(SELECT 1 FROM audit.SourceSnapshot WHERE SourceSnapshotKey=@SnapshotKey
        AND SourceFileHash IS NOT NULL AND SourceFileHash<>@SourceHash)
        THROW 51005,'Snapshot label is already associated with another source hash.',1;
    UPDATE audit.SourceSnapshot SET SourceFileHash=@SourceHash WHERE SourceSnapshotKey=@SnapshotKey;

    DECLARE @Date DATE='2016-01-01';
    WHILE @Date<='2018-12-31'
    BEGIN
        IF NOT EXISTS(SELECT 1 FROM dw.DimDate WHERE FullDate=@Date)
            INSERT dw.DimDate(DateKey,FullDate,CalendarYear,QuarterNumber,MonthNumber,MonthName,DayOfMonth,YearQuarter,YearMonth)
            VALUES(CONVERT(INT,CONVERT(CHAR(8),@Date,112)),@Date,YEAR(@Date),DATEPART(QUARTER,@Date),MONTH(@Date),
                DATENAME(MONTH,@Date),DAY(@Date),CONCAT(YEAR(@Date),'-Q',DATEPART(QUARTER,@Date)),
                CONCAT(YEAR(@Date),'-',RIGHT(CONCAT('0',MONTH(@Date)),2)));
        SET @Date=DATEADD(DAY,1,@Date);
    END;
    ;WITH IDs AS(
        SELECT household_id FROM stg.Transactions UNION SELECT household_id FROM stg.Demographics
        UNION SELECT household_id FROM stg.Campaigns UNION SELECT household_id FROM stg.CouponRedemptions)
    INSERT dw.DimHousehold(HouseholdID)
    SELECT household_id FROM IDs WHERE NULLIF(LTRIM(RTRIM(household_id)),'') IS NOT NULL
        AND NOT EXISTS(SELECT 1 FROM dw.DimHousehold h WHERE h.HouseholdID=IDs.household_id);
    -- Type 1 corrections: preserve keys, refresh current descriptions; no Type 2 history.
    UPDATE h SET AgeBand=ISNULL(d.age,'Unknown'),IncomeBand=ISNULL(d.income,'Unknown'),
        HomeOwnership=ISNULL(d.home_ownership,'Unknown'),MaritalStatus=ISNULL(d.marital_status,'Unknown'),
        HouseholdSizeBand=ISNULL(d.household_size,'Unknown'),HouseholdComposition=ISNULL(d.household_comp,'Unknown'),
        KidsCountBand=ISNULL(d.kids_count,'Unknown'),HasDemographics=CASE WHEN d.household_id IS NULL THEN 0 ELSE 1 END
    FROM dw.DimHousehold h LEFT JOIN stg.Demographics d ON h.HouseholdID=d.household_id;
    ;WITH IDs AS(SELECT product_id FROM stg.Transactions UNION SELECT product_id FROM stg.Products
        UNION SELECT product_id FROM stg.Coupons)
    INSERT dw.DimProduct(ProductID)
    SELECT product_id FROM IDs WHERE NULLIF(LTRIM(RTRIM(product_id)),'') IS NOT NULL
        AND NOT EXISTS(SELECT 1 FROM dw.DimProduct p WHERE p.ProductID=IDs.product_id);
    UPDATE p SET ManufacturerID=ISNULL(s.manufacturer_id,'Unknown'),Department=ISNULL(s.department,'Unknown'),
        Brand=ISNULL(s.brand,'Unknown'),ProductCategory=ISNULL(s.product_category,'Unknown'),
        ProductType=ISNULL(s.product_type,'Unknown'),PackageSize=ISNULL(s.package_size,'Unknown'),
        HasProductMetadata=CASE WHEN s.product_id IS NULL THEN 0 ELSE 1 END
    FROM dw.DimProduct p LEFT JOIN stg.Products s ON p.ProductID=s.product_id;
    INSERT dw.DimStore(StoreID) SELECT DISTINCT store_id FROM stg.Transactions t
    WHERE NOT EXISTS(SELECT 1 FROM dw.DimStore s WHERE s.StoreID=t.store_id);
    INSERT dw.DimCampaign(CampaignID) SELECT campaign_id FROM stg.CampaignDescriptions c
    WHERE NOT EXISTS(SELECT 1 FROM dw.DimCampaign d WHERE d.CampaignID=c.campaign_id);
    UPDATE d SET CampaignType=ISNULL(c.campaign_type,'Unknown'),StartDate=c.start_date,EndDate=c.end_date
    FROM dw.DimCampaign d JOIN stg.CampaignDescriptions c ON d.CampaignID=c.campaign_id;

    IF EXISTS(SELECT 1 FROM stg.Transactions t
        LEFT JOIN dw.DimDate d ON d.FullDate=CAST(t.transaction_timestamp AS DATE)
        LEFT JOIN dw.DimHousehold h ON h.HouseholdID=t.household_id
        LEFT JOIN dw.DimProduct p ON p.ProductID=t.product_id
        LEFT JOIN dw.DimStore s ON s.StoreID=t.store_id
        WHERE d.DateKey IS NULL OR h.HouseholdKey IS NULL OR p.ProductKey IS NULL OR s.StoreKey IS NULL)
        THROW 51006,'Unresolved sales dimension keys. No facts were replaced.',1;
    -- Migrate the old snapshot/row constraint: original row ordinal is not exported to SQL.
    -- Full replacement is the duplicate-load policy; no original row ordinal is invented.
    IF EXISTS(SELECT 1 FROM sys.key_constraints WHERE parent_object_id=OBJECT_ID('dw.FactSales') AND name='UQ_FactSales_Snapshot')
        ALTER TABLE dw.FactSales DROP CONSTRAINT UQ_FactSales_Snapshot;
    TRUNCATE TABLE dw.FactSales;
    INSERT dw.FactSales(DateKey,HouseholdKey,ProductKey,StoreKey,BasketID,TransactionTimestamp,
        SourceQuantity,SalesValue,RetailDiscount,CouponDiscount,CouponMatchDiscount,SourceWeek,
        IsZeroQuantity,IsZeroSales,SourceSnapshotKey,SourceRowNumber,LoadRunKey)
    SELECT d.DateKey,h.HouseholdKey,p.ProductKey,s.StoreKey,t.basket_id,t.transaction_timestamp,
        CAST(t.quantity AS DECIMAL(12,4)),m.Sales,m.Retail,m.Coupon,m.Match,t.week,
        CASE WHEN t.quantity=0 THEN 1 ELSE 0 END,CASE WHEN m.Sales=0 THEN 1 ELSE 0 END,
        @SnapshotKey,NULL,@LoadRunKey
    FROM stg.Transactions t JOIN dw.DimDate d ON d.FullDate=CAST(t.transaction_timestamp AS DATE)
    JOIN dw.DimHousehold h ON h.HouseholdID=t.household_id
    JOIN dw.DimProduct p ON p.ProductID=t.product_id JOIN dw.DimStore s ON s.StoreID=t.store_id
    CROSS APPLY(SELECT CAST(ROUND(t.sales_value,2) AS DECIMAL(19,2)),CAST(ROUND(t.retail_disc,2) AS DECIMAL(19,2)),
        CAST(ROUND(t.coupon_disc,2) AS DECIMAL(19,2)),CAST(ROUND(t.coupon_match_disc,2) AS DECIMAL(19,2)))m(Sales,Retail,Coupon,Match);
    DECLARE @Checks TABLE(Name VARCHAR(100),Expected DECIMAL(38,2),Actual DECIMAL(38,2));
    INSERT @Checks VALUES
    ('FactSales rows',1469307,(SELECT COUNT_BIG(*) FROM dw.FactSales)),
    ('SalesValue',4596039.58,(SELECT SUM(SalesValue) FROM dw.FactSales)),
    ('RetailDiscount',791650.64,(SELECT SUM(RetailDiscount) FROM dw.FactSales)),
    ('CouponDiscount',26359.90,(SELECT SUM(CouponDiscount) FROM dw.FactSales)),
    ('CouponMatchDiscount',4542.65,(SELECT SUM(CouponMatchDiscount) FROM dw.FactSales)),
    ('Distinct baskets',155848,(SELECT COUNT(DISTINCT BasketID) FROM dw.FactSales)),
    ('Purchasing households',2469,(SELECT COUNT(DISTINCT HouseholdKey) FROM dw.FactSales)),
    ('Stores',457,(SELECT COUNT(DISTINCT StoreKey) FROM dw.FactSales)),
    ('Product metadata members',92331,(SELECT COUNT(*) FROM dw.DimProduct WHERE HasProductMetadata=1)),
    ('Missing fact batch references',0,(SELECT COUNT(*) FROM dw.FactSales WHERE SourceSnapshotKey IS NULL OR LoadRunKey IS NULL));
    IF EXISTS(SELECT 1 FROM @Checks WHERE Actual IS NULL OR Expected<>Actual)
        THROW 51007,'Warehouse reconciliation failed. The previous warehouse will be restored.',1;
    INSERT audit.ReconciliationCheck(LoadRunKey,CheckName,ExpectedValue,ActualValue,Passed)
    SELECT @LoadRunKey,CONCAT('Staging ',Name),CONVERT(VARCHAR(50),Expected),CONVERT(VARCHAR(50),Actual),1 FROM @Counts;
    INSERT audit.ReconciliationCheck(LoadRunKey,CheckName,ExpectedValue,ActualValue,Passed)
    SELECT @LoadRunKey,Name,CONVERT(VARCHAR(50),Expected),CONVERT(VARCHAR(50),Actual),1 FROM @Checks;
    UPDATE audit.LoadRun SET Status='SUCCESS',CompletedAt=SYSDATETIME(),Notes='Full refresh passed all release checks; SourceRowNumber remains NULL.' WHERE LoadRunKey=@LoadRunKey;
    COMMIT;
    EXEC sys.sp_releaseapplock @Resource='CompleteJourneyDW_FullRefresh',@LockOwner='Session';
    SELECT * FROM audit.ReconciliationCheck WHERE LoadRunKey=@LoadRunKey ORDER BY CheckKey;
END TRY
BEGIN CATCH
    DECLARE @Error NVARCHAR(500)=LEFT(ERROR_MESSAGE(),500);
    IF XACT_STATE()<>0 ROLLBACK;
    UPDATE audit.LoadRun SET Status='FAILED',CompletedAt=SYSDATETIME(),Notes=@Error WHERE LoadRunKey=@LoadRunKey;
    INSERT audit.ReconciliationCheck(LoadRunKey,CheckName,ExpectedValue,ActualValue,Passed)
        VALUES(@LoadRunKey,'Refresh completed','SUCCESS','FAILED',0);
    EXEC sys.sp_releaseapplock @Resource='CompleteJourneyDW_FullRefresh',@LockOwner='Session';
    THROW;
END CATCH;
GO
