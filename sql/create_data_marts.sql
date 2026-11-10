USE CompleteJourneyDW;
GO
CREATE OR ALTER VIEW mart.CategoryPerformance AS
SELECT d.YearMonth,d.CalendarYear,d.MonthName,p.Department,p.ProductCategory,p.ProductType,
    SUM(f.SalesValue) AS TotalSalesValue,
    SUM(f.RetailDiscount) AS RetailDiscounts,
    SUM(f.CouponDiscount) AS ManufacturerCouponDiscounts,
    SUM(f.CouponMatchDiscount) AS CouponMatchDiscounts,
    SUM(f.RetailDiscount+f.CouponDiscount+f.CouponMatchDiscount) AS CombinedRecordedDiscounts,
    SUM(f.SourceQuantity) AS TotalSourceQuantity
FROM dw.FactSales f JOIN dw.DimDate d ON f.DateKey=d.DateKey
JOIN dw.DimProduct p ON f.ProductKey=p.ProductKey
GROUP BY d.YearMonth,d.CalendarYear,d.MonthName,p.Department,p.ProductCategory,p.ProductType;
GO
-- Standard view, not materialised. TotalSourceQuantity requires compatible units.
