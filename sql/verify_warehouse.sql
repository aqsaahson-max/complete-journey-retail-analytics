USE CompleteJourneyDW;
GO
SELECT COUNT_BIG(*) AS FactRows,SUM(SalesValue) AS Sales,SUM(RetailDiscount) AS RetailDiscounts,
SUM(CouponDiscount) AS ManufacturerCouponDiscounts,SUM(CouponMatchDiscount) AS CouponMatchDiscounts,
COUNT(DISTINCT BasketID) AS Baskets,COUNT(DISTINCT HouseholdKey) AS Households FROM dw.FactSales;
SELECT HasProductMetadata,COUNT(*) AS Products FROM dw.DimProduct GROUP BY HasProductMetadata;
SELECT TOP (5) * FROM audit.LoadRun ORDER BY LoadRunKey DESC;
SELECT * FROM audit.ReconciliationCheck WHERE LoadRunKey=(SELECT MAX(LoadRunKey) FROM audit.LoadRun);
SELECT SUM(TotalSalesValue) AS MartSales,SUM(RetailDiscounts) AS MartRetailDiscounts,
SUM(CombinedRecordedDiscounts) AS MartCombinedDiscounts FROM mart.CategoryPerformance;
SELECT ProductID,HasProductMetadata FROM dw.DimProduct WHERE ProductID IN ('1003998','469192','9796410');
GO
