-- create database and schemas
CREATE DATABASE CompleteJourneyDW;
GO
USE CompleteJourneyDW;
GO
CREATE SCHEMA stg;   -- staging: raw CSV data lands here
GO
CREATE SCHEMA dw;    -- dimensional warehouse: star schema lives here
GO
CREATE SCHEMA audit; -- audit: load tracking and reconciliation
GO
CREATE SCHEMA mart;  -- departmental mart: curated views for Power BI
GO

--Create audit tables
-- Batch-level audit structures. The full-refresh loader records runs and reconciliation.
-- SourceRowNumber is reserved; original row provenance remains in Parquet.
-- Registers each source file snapshot (one row per dataset version)
CREATE TABLE audit.SourceSnapshot (
    SourceSnapshotKey INT IDENTITY(1,1) PRIMARY KEY,
    SnapshotLabel     VARCHAR(200) NOT NULL,    -- e.g. 'completejourney_v1_2026-09-29'
    SourceFileHash    VARCHAR(64),              -- optional SHA-256 of the source
    RegisteredAt      DATETIME2(7) DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_SourceSnapshot_Label UNIQUE (SnapshotLabel)
);

-- Logs each ETL execution
CREATE TABLE audit.LoadRun (
    LoadRunKey    INT IDENTITY(1,1) PRIMARY KEY,
    StartedAt     DATETIME2(7) DEFAULT SYSDATETIME(),
    CompletedAt   DATETIME2(7),
    Status        VARCHAR(20) DEFAULT 'RUNNING', -- RUNNING / SUCCESS / FAILED
    Notes         NVARCHAR(500)
);

-- Reconciliation results per run
CREATE TABLE audit.ReconciliationCheck (
    CheckKey      INT IDENTITY(1,1) PRIMARY KEY,
    LoadRunKey    INT REFERENCES audit.LoadRun(LoadRunKey),
    CheckName     VARCHAR(100),
    ExpectedValue VARCHAR(50),
    ActualValue   VARCHAR(50),
    Passed        BIT,
    CheckedAt     DATETIME2(7) DEFAULT SYSDATETIME()
);

CREATE TABLE stg.Transactions (
    household_id          VARCHAR(20),
    basket_id             VARCHAR(20),
    product_id            VARCHAR(20),
    quantity              FLOAT,          -- keep source precision, transform later
    sales_value           FLOAT,
    retail_disc           FLOAT,
    coupon_disc           FLOAT,
    coupon_match_disc     FLOAT,
    week                  INT,
    store_id              VARCHAR(20),
    transaction_timestamp DATETIME2(7)
);

-- Create staging tables
-- These hold raw source values with no transformations â€” just text and basic types matching the CSV columns.
CREATE TABLE stg.Products (
    product_id       VARCHAR(20),
    manufacturer_id  VARCHAR(20),
    department       VARCHAR(100),
    brand            VARCHAR(100),
    product_category VARCHAR(100),
    product_type     VARCHAR(100),
    package_size     VARCHAR(100)
);

CREATE TABLE stg.Demographics (
    household_id  VARCHAR(20),
    age           VARCHAR(50),
    income        VARCHAR(50),
    home_ownership VARCHAR(50),
    marital_status VARCHAR(50),
    household_size VARCHAR(50),
    household_comp VARCHAR(50),
    kids_count     VARCHAR(50)
);

CREATE TABLE stg.Campaigns (
    household_id VARCHAR(20),
    campaign_id  VARCHAR(20)
);

CREATE TABLE stg.CampaignDescriptions (
    campaign_id  VARCHAR(20),
    campaign_type VARCHAR(20),
    start_date   DATE,
    end_date     DATE
);

CREATE TABLE stg.Coupons (
    campaign_id VARCHAR(20),
    coupon_upc  VARCHAR(30),
    product_id  VARCHAR(20)
);

CREATE TABLE stg.CouponRedemptions (
    household_id    VARCHAR(20),
    coupon_upc      VARCHAR(30),
    campaign_id     VARCHAR(20),
    redemption_date DATE
);

--  Create dimension tables (dw schema)
-- DimDate: generated calendar, not loaded from CSV
CREATE TABLE dw.DimDate (
    DateKey       INT          PRIMARY KEY,  -- YYYYMMDD format
    FullDate      DATE         NOT NULL UNIQUE,
    CalendarYear  INT          NOT NULL,
    QuarterNumber INT          NOT NULL,
    MonthNumber   INT          NOT NULL,
    MonthName     VARCHAR(15)  NOT NULL,
    DayOfMonth    INT          NOT NULL,
    YearQuarter   VARCHAR(7)   NOT NULL,     -- e.g. '2017-Q3'
    YearMonth     VARCHAR(7)   NOT NULL      -- e.g. '2017-08'
);

-- DimHousehold: union of all household IDs + optional demographics
CREATE TABLE dw.DimHousehold (
    HouseholdKey        INT IDENTITY(1,1) PRIMARY KEY,
    HouseholdID         VARCHAR(20)  NOT NULL UNIQUE,
    AgeBand             VARCHAR(50),
    IncomeBand          VARCHAR(50),
    HomeOwnership       VARCHAR(50),
    MaritalStatus       VARCHAR(50),
    HouseholdSizeBand   VARCHAR(50),
    HouseholdComposition VARCHAR(50),
    KidsCountBand       VARCHAR(50),
    HasDemographics     BIT          NOT NULL DEFAULT 0
);

-- DimProduct: union of all product IDs + optional metadata
CREATE TABLE dw.DimProduct (
    ProductKey        INT IDENTITY(1,1) PRIMARY KEY,
    ProductID         VARCHAR(20)  NOT NULL UNIQUE,
    ManufacturerID    VARCHAR(20),
    Department        VARCHAR(100),
    Brand             VARCHAR(100),
    ProductCategory   VARCHAR(100),
    ProductType       VARCHAR(100),
    PackageSize       VARCHAR(100),
    HasProductMetadata BIT          NOT NULL DEFAULT 0
);

-- DimStore: store identifiers only (no location data available)
CREATE TABLE dw.DimStore (
    StoreKey INT IDENTITY(1,1) PRIMARY KEY,
    StoreID  VARCHAR(20) NOT NULL UNIQUE
);

-- dw.DimCampaign
  CREATE TABLE dw.DimCampaign (
      CampaignKey INT IDENTITY(1,1) PRIMARY KEY,
      CampaignID  VARCHAR(20) NOT NULL UNIQUE,
      CampaignType VARCHAR(20),
      StartDate   DATE,
      EndDate     DATE
  );

-- Create the fact table
CREATE TABLE dw.FactSales (
    SalesKey             BIGINT IDENTITY(1,1) PRIMARY KEY,
    DateKey              INT          NOT NULL REFERENCES dw.DimDate(DateKey),
    HouseholdKey         INT          NOT NULL REFERENCES dw.DimHousehold(HouseholdKey),
    ProductKey           INT          NOT NULL REFERENCES dw.DimProduct(ProductKey),
    StoreKey             INT          NOT NULL REFERENCES dw.DimStore(StoreKey),
    BasketID             VARCHAR(20)  NOT NULL,
    TransactionTimestamp DATETIME2(7) NOT NULL,
    SourceQuantity       DECIMAL(12,4),  -- preserves fractional source precision
    SalesValue           DECIMAL(19,2) NOT NULL,
    RetailDiscount       DECIMAL(19,2) NOT NULL,
    CouponDiscount       DECIMAL(19,2) NOT NULL,
    CouponMatchDiscount  DECIMAL(19,2) NOT NULL,
    SourceWeek           INT,
    IsZeroQuantity       BIT          NOT NULL DEFAULT 0,
    IsZeroSales          BIT          NOT NULL DEFAULT 0,
    SourceSnapshotKey    INT          REFERENCES audit.SourceSnapshot(SourceSnapshotKey),
    SourceRowNumber      INT,
    LoadRunKey           INT          REFERENCES audit.LoadRun(LoadRunKey)
);




