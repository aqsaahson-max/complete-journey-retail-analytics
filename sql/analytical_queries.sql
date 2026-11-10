USE CompleteJourneyDW;
GO
-- Monthly sales: year is retained in the period label.
SELECT d.YearMonth,SUM(f.SalesValue) AS Sales FROM dw.FactSales f
JOIN dw.DimDate d ON d.DateKey=f.DateKey GROUP BY d.YearMonth ORDER BY d.YearMonth;
GO
-- Category ranking within each department, including tied ranks.
WITH CategorySales AS(SELECT p.Department,p.ProductCategory,SUM(f.SalesValue) AS Sales
FROM dw.FactSales f JOIN dw.DimProduct p ON p.ProductKey=f.ProductKey GROUP BY p.Department,p.ProductCategory),
Ranked AS(SELECT *,RANK() OVER(PARTITION BY Department ORDER BY Sales DESC) AS CategoryRank FROM CategorySales)
SELECT * FROM Ranked WHERE CategoryRank<=3 ORDER BY Department,CategoryRank,ProductCategory;
GO
-- Daily running sales total with an explicit row frame.
WITH Daily AS(SELECT d.FullDate,SUM(f.SalesValue) AS Sales FROM dw.FactSales f
JOIN dw.DimDate d ON d.DateKey=f.DateKey GROUP BY d.FullDate)
SELECT FullDate,Sales,SUM(Sales) OVER(ORDER BY FullDate ROWS UNBOUNDED PRECEDING) AS RunningSales FROM Daily ORDER BY FullDate;
GO
-- Highest-sales stores, retaining ties.
WITH StoreSales AS(SELECT s.StoreID,SUM(f.SalesValue) AS Sales FROM dw.FactSales f
JOIN dw.DimStore s ON s.StoreKey=f.StoreKey GROUP BY s.StoreID)
SELECT * FROM StoreSales WHERE Sales=(SELECT MAX(Sales) FROM StoreSales);
GO
