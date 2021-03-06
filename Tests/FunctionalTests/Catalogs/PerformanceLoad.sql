USE [VirtoCommerce]
GO

SET NOCOUNT ON; --For performance boost

 --Settings
DECLARE @catalogId nvarchar(20) = N'PTest';
DECLARE @categoryPrefixId nvarchar(20) = N'PTestCat';
DECLARE @itemPrefixId nvarchar(20) = N'i-';
DECLARE @propertyPrefixId nvarchar(20) = N'PTestProp';
DECLARE @priceListPrefixId nvarchar(20) = N'PTestPriceList';
DECLARE @categoryCount int = 10				--How many categories to generate
DECLARE @itemCount int = 500000				--How many variations to generate
DECLARE @startItemIndex int = 0				--Starting index for item
DECLARE @endItemIndex int = @itemCount + @startItemIndex
DECLARE @orderCount int = 1000000			--How many orders to generate
DECLARE @associationCount int = 2			--How many items to associate (ex. 2 means every 2'nd item will have associated previous 2 items)
DECLARE @itemRelationCount int = 2			--How many item relations to generate
DECLARE @priceListCount int = 2				--How many price lists to generate
DECLARE @generateCatalogItems bit = 1		--Should variations be generated
DECLARE @generateOrders bit = 0				--Should orders be generated
DECLARE @initial bit = 1					--Is initial run
DECLARE @maxLogFileSizeMB int = 5000		--Maximum size of log file before calling shrink
DECLARE @disableIndexes bit = 1				--Should indexes be disabled (rebuild takes time)

DECLARE @chunkSize int = 10000			--Chunk size for one transaction

DECLARE  @PropertiesTable TABLE(
Id nvarchar(2),
Value varchar(50),
IsRelation bit)

INSERT INTO @PropertiesTable
SELECT p.Id, p.Value, p.IsRelation
FROM (SELECT 'Title' as Value, '0' as Id, 0 as IsRelation UNION
	  SELECT 'Color' as Value, '1' as Id, 1 as IsRelation UNION
	  SELECT 'Size'  as Value, '2' as Id, 1 as IsRelation) p


--Globals
DECLARE @i int = 0;
DECLARE @now datetime = GETDATE()
DECLARE @lastModified datetime = NULL
DECLARE @startDate datetime = dateadd(year,-1, @now)
DECLARE @endDate datetime = dateadd(year,1, @now)
DECLARE @idSuffix varchar(10) = ''

IF @generateCatalogItems = 1
BEGIN
IF @initial = 1
	BEGIN
		BEGIN TRANSACTION
			 DECLARE @propertySetId nvarchar(128) = NEWID()

			--Create catalog
			 INSERT INTO [dbo].[CatalogBase]
			 VALUES(@catalogId,'Performance test catalog','en-us',NULL,NULL,@now)

			 INSERT INTO [dbo].[Catalog]
			 VALUES(@catalogId, 1)

			 --Create properties
			 INSERT INTO [dbo].[PropertySet]
			 VALUES(@propertySetId,N'Performance test property set','All',@catalogId,@lastModified,@now,N'PropertySet')

			 INSERT INTO [dbo].[Property]
			 SELECT @propertyPrefixId + props.Id, props.Value,0,0,0,0,0,0,0,0,0,NULL,@catalogId,@lastModified,@now,N'Property'
			 FROM @PropertiesTable props

			 INSERT INTO [dbo].[PropertySetProperty]
			 SELECT NEWID(),0,props.PropertyId,@propertySetId, @lastModified,@now,N'PropertySetProperty'
			 FROM [dbo].[Property] props
			 where props.PropertyId LIKE @propertyPrefixId + '%'

		COMMIT TRANSACTION
		BEGIN TRANSACTION

			--Create categories
			SET @i = 0;
			WHILE @i < @categoryCount
			BEGIN

			  SET @idSuffix = CONVERT(varchar(10), @i)

			  INSERT INTO [dbo].[CategoryBase]
			  VALUES(@categoryPrefixId + @idSuffix,'performance-test-category-'+ @idSuffix,1,0, @catalogId,NULL,@lastModified, @now)
			  INSERT INTO [dbo].[Category]
			  VALUES(@categoryPrefixId + @idSuffix,'Performance test category '+ @idSuffix, @startDate, @endDate, @propertySetId)
			  SET @i += 1;
			END
		COMMIT TRANSACTION
		BEGIN TRANSACTION

			--Generate price lists
			DECLARE @priceIdx int = 0
			WHILE @priceIdx < @priceListCount
			BEGIN
				SET @idSuffix = CONVERT(varchar(10), @priceIdx)
				DECLARE @priceListId nvarchar(128) = @priceListPrefixId + @idSuffix
				DECLARE @currency nvarchar(3)= CASE @priceIdx
					WHEN 0 THEN 'EUR'
					ELSE 'USD'
				END

				INSERT INTO [dbo].[Pricelist]
				VALUES(@priceListId,'PTestPrices' + @idSuffix,NULL,@currency,@lastModified,@now,N'Pricelist')

				INSERT INTO [dbo].[PricelistAssignment]
				VALUES( NEWID(),'PTestSale'+ @currency,'Performace test sale in '+@currency,0,@startDate,@endDate,NULL,NULL,@priceListId,@catalogId,@lastModified,@now,N'PricelistAssignment')

				SET @priceIdx += 1;
			END
		COMMIT TRANSACTION
	END

	--Create variations

	IF @disableIndexes = 1
	BEGIN
	--DISABLE INDEXES BEFORE INSERT
	PRINT 'Droping indexes...'
	DROP INDEX IX_Code_CatalogId ON [dbo].[Item]
	DROP INDEX IX_Discriminator ON [dbo].[Item]
	DROP INDEX IX_LastModified ON [dbo].[Item]
	DROP INDEX IX_PropertySetId ON [dbo].[Item]
	DROP INDEX IX_CatalogId ON [dbo].[Item]
	DROP INDEX IX_AssociationGroupId ON [dbo].[Association]
	DROP INDEX IX_ItemId ON [dbo].[Association]
	DROP INDEX IX_ItemId ON [dbo].[AssociationGroup]
	DROP INDEX IX_CatalogId ON [dbo].[CategoryItemRelation]
	DROP INDEX IX_CategoryId ON [dbo].[CategoryItemRelation]
	DROP INDEX IX_ItemId ON [dbo].[CategoryItemRelation]
	DROP INDEX IX_ChildItemId ON [dbo].[ItemRelation]
	DROP INDEX IX_ParentItemId ON [dbo].[ItemRelation]
	DROP INDEX IX_ItemId ON [dbo].[ItemPropertyValue]

	PRINT 'Disabling foreign key constrains...'
	ALTER TABLE [dbo].[Item] NOCHECK CONSTRAINT [FK_dbo.Item_dbo.CatalogBase_CatalogId]
	ALTER TABLE [dbo].[Item] NOCHECK CONSTRAINT [FK_dbo.Item_dbo.PropertySet_PropertySetId]
	ALTER TABLE [dbo].[Association] NOCHECK CONSTRAINT [FK_dbo.Association_dbo.AssociationGroup_AssociationGroupId]
	ALTER TABLE [dbo].[Association] NOCHECK CONSTRAINT [FK_dbo.Association_dbo.Item_ItemId]
	ALTER TABLE [dbo].[AssociationGroup] NOCHECK CONSTRAINT [FK_dbo.AssociationGroup_dbo.Item_ItemId]
	ALTER TABLE [dbo].[CategoryItemRelation] NOCHECK CONSTRAINT [FK_dbo.CategoryItemRelation_dbo.CatalogBase_CatalogId]
	ALTER TABLE [dbo].[CategoryItemRelation] NOCHECK CONSTRAINT [FK_dbo.CategoryItemRelation_dbo.CategoryBase_CategoryId]
	ALTER TABLE [dbo].[CategoryItemRelation] NOCHECK CONSTRAINT [FK_dbo.CategoryItemRelation_dbo.Item_ItemId]
	ALTER TABLE [dbo].[ItemRelation] NOCHECK CONSTRAINT [FK_dbo.ItemRelation_dbo.Item_ChildItemId]
	ALTER TABLE [dbo].[ItemRelation] NOCHECK CONSTRAINT [FK_dbo.ItemRelation_dbo.Item_ParentItemId]
	ALTER TABLE [dbo].[ItemPropertyValue] NOCHECK CONSTRAINT [FK_dbo.ItemPropertyValue_dbo.Item_ItemId]

	END

	SET @i = @startItemIndex;
	WHILE @i < @endItemIndex
	BEGIN
		
		DECLARE @chunkIdx int = 0;
		DECLARE @maxSize int = @chunkSize

		IF @maxSize > @endItemIndex - @i 
		BEGIN
			SET @maxSize = @endItemIndex - @i
		END

		BEGIN TRANSACTION
		WHILE @chunkIdx < @maxSize
		BEGIN	

			SET @idSuffix = CONVERT(varchar(10), @i)
			DECLARE @itemId nvarchar(128) =  @itemPrefixId + @idSuffix
			DECLARE @lastItemId nvarchar(128) = @itemId

			--Generate items
			INSERT INTO [dbo].[Item]
			VALUES(@itemId,'Performance test product ' + @idSuffix, @startDate,@endDate,1,1,0,1,10,0,0,0,NULL,@itemId,@propertySetId,@catalogId,@lastModified,@now,'Sku')

			INSERT INTO [dbo].[CategoryItemRelation]
			VALUES(NEWID(),0, @itemId, @categoryPrefixId+ CONVERT(varchar(1), (@i-@startItemIndex)/(@itemCount/@categoryCount)), @catalogId, @lastModified, @now,'CategoryItemRelation')

			--Generate associations
			IF @i % @associationCount = 0 AND @i > @startItemIndex --Parent item is every associationCount'th
			BEGIN

				DECLARE @assocInx int = 0
				DECLARE @associationGroup1Id nvarchar(128) = NEWID()
				DECLARE @associationGroup2Id nvarchar(128) = NEWID()

				INSERT INTO [dbo].[AssociationGroup]
				VALUES(@associationGroup1Id, 'Related Items',NULL,0, @itemId, @lastModified,@now,N'AssociationGroup')
				INSERT INTO [dbo].[AssociationGroup]
				VALUES(@associationGroup2Id, 'Accessories',NULL,0, @itemId, @lastModified,@now,N'AssociationGroup')

				WHILE @assocInx < @associationCount
				BEGIN
					SET @lastItemId  = @itemPrefixId + CONVERT(varchar(10), @i-1-@assocInx)
					INSERT INTO [dbo].[Association]
					VALUES(NEWID(),'optional', 0, 
					CASE @assocInx % 2 
						WHEN 0 
						THEN @associationGroup1Id
						ELSE @associationGroup2Id 
					END, @lastItemId ,@lastModified,@now,N'Association')

					SET @assocInx += 1;
				END
			END

			--Generate item relations
			IF @i % @itemRelationCount = 0 AND @i > @startItemIndex --Parent item is every itemRelationCount'th
			BEGIN
				DECLARE @relInx int = 0
				WHILE @relInx < @itemRelationCount
				BEGIN

					SET @lastItemId = @itemPrefixId + CONVERT(varchar(10), @i-1-@relInx)

					INSERT INTO [dbo].[ItemRelation]
					SELECT NEWID(),NULL,1,p.Value,0,@lastItemId,@itemId, @lastModified,@now,N'ItemRelation'
					FROM @PropertiesTable p 
					WHERE p.IsRelation = 1

					SET @relInx += 1;
				END
			END


			--Generate item property values
			INSERT INTO [dbo].[ItemPropertyValue]
			SELECT NEWID(),@itemId,NULL, props.Value,NULL,0,(
			CASE props.Value
				WHEN 'Color' THEN
					CASE ABS(CHECKSUM(NEWID()) % 5)
						WHEN 0 THEN 'Red'
						WHEN 1 THEN 'Green'
						WHEN 2 THEN 'Blue'
						WHEN 3 THEN 'White'
						ELSE 'Black'
					END
				WHEN 'Size' THEN
					CASE ABS(CHECKSUM(NEWID()) % 5)
						WHEN 0 THEN 'S'
						WHEN 1 THEN 'M'
						WHEN 2 THEN 'L'
						WHEN 3 THEN 'XL'
						ELSE 'XXL'
					END
				WHEN 'Title' THEN 'Performance test product ' + @idSuffix
				ELSE 'Unknown'
			END),NULL,0,0,0,NULL,'en-US',@lastModified,@now
			FROM @PropertiesTable props

			--Add prices
			SET @priceIdx = 0
			WHILE @priceIdx < @priceListCount
			BEGIN
				INSERT INTO [dbo].[Price]
				VALUES(NEWID(),NULL,100.0,1,@priceListPrefixId + CONVERT(varchar(10), @priceIdx),@itemId,@lastModified,@now,N'Price')
				SET @priceIdx += 1;
			END

			SET @chunkIdx += 1;
			SET @i += 1;
		END
		COMMIT TRANSACTION

		PRINT Convert(varchar, @i*100/@itemCount) + '% of items created'

		--DECLARE @size int = (SELECT (size*8)/1024 SizeMB
		--FROM [master].[sys].[master_files] as msfiles
		--WHERE DB_NAME(database_id) = 'VirtoCommerce' AND 
		--msfiles.name = 'VirtoCommerce_log')

		----When size of log file reaches threashold shrink it
		--IF @size > @maxLogFileSizeMB
		--BEGIN
		--	PRINT 'Shrinking log file'
		--	--DBCC SHRINKFILE(VirtoCommerce_log, 1)
		--END
	END

	IF @disableIndexes = 1
	BEGIN
	--ENABLE INDEXES AFTER INSERT
	PRINT 'Creating indexes...'
	CREATE UNIQUE NONCLUSTERED INDEX IX_Code_CatalogId ON [dbo].[Item]([Code] ASC,[CatalogId] ASC)
	CREATE NONCLUSTERED INDEX IX_Discriminator ON [dbo].[Item](Discriminator ASC)
	CREATE NONCLUSTERED INDEX IX_LastModified ON [dbo].[Item](LastModified ASC)
	CREATE NONCLUSTERED INDEX IX_PropertySetId ON [dbo].[Item](PropertySetId ASC)
	CREATE NONCLUSTERED INDEX IX_CatalogId ON [dbo].[Item](CatalogId ASC)
	CREATE NONCLUSTERED INDEX IX_AssociationGroupId ON [dbo].[Association](AssociationGroupId ASC)
	CREATE NONCLUSTERED INDEX IX_ItemId ON [dbo].[Association](ItemId ASC)
	CREATE NONCLUSTERED INDEX IX_ItemId ON [dbo].[AssociationGroup](ItemId ASC)
	CREATE NONCLUSTERED INDEX IX_CatalogId ON [dbo].[CategoryItemRelation](CatalogId ASC)
	CREATE NONCLUSTERED INDEX IX_CategoryId ON [dbo].[CategoryItemRelation](CategoryId ASC)
	CREATE NONCLUSTERED INDEX IX_ItemId ON [dbo].[CategoryItemRelation](ItemId  ASC)
	CREATE NONCLUSTERED INDEX IX_ChildItemId ON [dbo].[ItemRelation](ChildItemId ASC)
	CREATE NONCLUSTERED INDEX IX_ParentItemId ON [dbo].[ItemRelation](ParentItemId ASC)
	CREATE NONCLUSTERED INDEX IX_ItemId ON [dbo].[ItemPropertyValue](ItemId ASC)

	PRINT 'Enabling foreign key constrains...'
	ALTER TABLE [dbo].[Item] WITH CHECK CHECK CONSTRAINT [FK_dbo.Item_dbo.CatalogBase_CatalogId]
	ALTER TABLE [dbo].[Item] WITH CHECK CHECK CONSTRAINT [FK_dbo.Item_dbo.PropertySet_PropertySetId]
	ALTER TABLE [dbo].[Association] WITH CHECK CHECK CONSTRAINT [FK_dbo.Association_dbo.AssociationGroup_AssociationGroupId]
	ALTER TABLE [dbo].[Association] WITH CHECK CHECK CONSTRAINT [FK_dbo.Association_dbo.Item_ItemId]
	ALTER TABLE [dbo].[AssociationGroup] WITH CHECK CHECK CONSTRAINT [FK_dbo.AssociationGroup_dbo.Item_ItemId]
	ALTER TABLE [dbo].[CategoryItemRelation] WITH CHECK CHECK CONSTRAINT [FK_dbo.CategoryItemRelation_dbo.CatalogBase_CatalogId]
	ALTER TABLE [dbo].[CategoryItemRelation] WITH CHECK CHECK CONSTRAINT [FK_dbo.CategoryItemRelation_dbo.CategoryBase_CategoryId]
	ALTER TABLE [dbo].[CategoryItemRelation] WITH CHECK CHECK CONSTRAINT [FK_dbo.CategoryItemRelation_dbo.Item_ItemId]
	ALTER TABLE [dbo].[ItemRelation] WITH CHECK CHECK CONSTRAINT [FK_dbo.ItemRelation_dbo.Item_ChildItemId]
	ALTER TABLE [dbo].[ItemRelation] WITH CHECK CHECK CONSTRAINT [FK_dbo.ItemRelation_dbo.Item_ParentItemId]
	ALTER TABLE [dbo].[ItemPropertyValue] WITH CHECK CHECK CONSTRAINT [FK_dbo.ItemPropertyValue_dbo.Item_ItemId]
	END
END


--Generate orders
IF @generateOrders = 1
BEGIN
	--DISABLE INDEXES BEFORE INSERT
	IF @disableIndexes = 1
	BEGIN
	PRINT 'Droping indexes...'
	DROP INDEX IX_OrderGroupId ON [dbo].[OrderForm]
	DROP INDEX IX_OrderFormId ON [dbo].[LineItem]
	DROP INDEX IX_OrderFormId ON [dbo].[Shipment]
	DROP INDEX IX_PicklistId ON [dbo].[Shipment]
	DROP INDEX IX_LineItemId ON [dbo].[ShipmentItem]
	DROP INDEX IX_ShipmentId ON [dbo].[ShipmentItem]

	PRINT 'Disabling foreign key constrains...'
	ALTER TABLE [dbo].[OrderForm] NOCHECK CONSTRAINT [FK_dbo.OrderForm_dbo.OrderGroup_OrderGroupId]
	ALTER TABLE [dbo].[LineItem] NOCHECK CONSTRAINT [FK_dbo.LineItem_dbo.OrderForm_OrderFormId]
	ALTER TABLE [dbo].[Shipment] NOCHECK CONSTRAINT [FK_dbo.Shipment_dbo.OrderForm_OrderFormId]
	ALTER TABLE [dbo].[Shipment] NOCHECK CONSTRAINT [FK_dbo.Shipment_dbo.Picklist_PicklistId]
	ALTER TABLE [dbo].[ShipmentItem] NOCHECK CONSTRAINT [FK_dbo.ShipmentItem_dbo.LineItem_LineItemId]
	ALTER TABLE [dbo].[ShipmentItem] NOCHECK CONSTRAINT [FK_dbo.ShipmentItem_dbo.Shipment_ShipmentId]
	END

	SET @i = 0;
	WHILE @i < @orderCount
	BEGIN
		SET @chunkIdx  = 0;
		SET @maxSize  = @chunkSize

		IF @maxSize > @orderCount - @i 
		BEGIN
			SET @maxSize = @orderCount - @i
		END

		BEGIN TRANSACTION
		WHILE @chunkIdx < @maxSize
		BEGIN	
			DECLARE @orderGroupId nvarchar(128) = NEWID()
			DECLARE @orderFormId nvarchar(128) = NEWID()	
			DECLARE @shipmentId nvarchar(128) = NEWID()
			DECLARE @lineItemId nvarchar(128) = NEWID()

			INSERT INTO [dbo].[OrderGroup]
			VALUES(@orderGroupId,'default', NULL,2,'Test, User','SampleStore',NULL,10.12,1.20,4.44,123.43,124.53,'USD','InProgress',@lastModified,@now,
			'ORDER'+ CONVERT(varchar(4), datepart(YEAR,@now)) + '-' + CONVERT(varchar(2), datepart(MONTH,@now)) + CONVERT(varchar(2), datepart(DAY,@now)) + '-' + CONVERT(varchar(10), @i), 
			NULL,NULL,'Order')

			INSERT INTO [dbo].[OrderForm]
			VALUES(@orderFormId, @orderGroupId, 'default',NULL,NULL,0,0,0,0,0,0,@lastModified,@now,'OrderForm')

			INSERT INTO [dbo].[LineItem]
			VALUES(@lineItemId,@orderFormId,@catalogId,@categoryPrefixId + '0',N'FreeShipping',
			@catalogId + '/' + @categoryPrefixId + '0',@itemPrefixId + '0',NULL,@itemPrefixId + '0',
			1,1,10,100.0,10.0,110.0,0,10,0,0,NULL,N'FreeShipping',100.0,
			NULL,NULL,'Performance test product 0',0,0,NULL,NULL,NULL,@lastModified,@now,N'LineItem')
			
			INSERT INTO [dbo].[Shipment]
			VALUES (@shipmentId, N'FreeShipping',N'FreeShipping',NULL,NULL,NULL,200.12,5.01,0.00,0.35,195.12,213.12,119.00,5.99,NULL,@orderFormId,NULL,@lastModified,@now,N'Shipment');
		
			INSERT INTO [dbo].[ShipmentItem]
			VALUES (NEWID(),18.00,@lineItemId,@shipmentId,@lastModified,@now,N'ShipmentItem');

			SET @i += 1;
			SET @chunkIdx += 1;
		END
		COMMIT TRANSACTION

		PRINT Convert(varchar, @i*100/@orderCount) + '% of orders created'
		

		--SET @size = (SELECT (size*8)/1024 SizeMB
		--FROM [master].[sys].[master_files] as msfiles
		--WHERE DB_NAME(database_id) = 'VirtoCommerce' AND 
		--msfiles.name = 'VirtoCommerce_log')

		----When size of log file reaches threashold shrink it
		--IF @size > @maxLogFileSizeMB
		--BEGIN
		--	PRINT 'Shrinking log file'
		--	--DBCC SHRINKFILE(VirtoCommerce_log, 1)
		--END
	END

	--ENALBE INDEXES AFTER INSERT
	IF @disableIndexes = 1
	BEGIN
	PRINT 'Creating indexes...'
	CREATE NONCLUSTERED INDEX IX_OrderGroupId ON [dbo].[OrderForm] (OrderGroupId ASC)
	CREATE NONCLUSTERED INDEX IX_OrderFormId ON [dbo].[LineItem] (OrderFormId ASC)
	CREATE NONCLUSTERED INDEX IX_OrderFormId ON [dbo].[Shipment] (OrderFormId ASC)
	CREATE NONCLUSTERED INDEX IX_PicklistId ON [dbo].[Shipment] (PicklistId ASC)
	CREATE NONCLUSTERED INDEX IX_LineItemId ON [dbo].[ShipmentItem] (LineItemId ASC)
	CREATE NONCLUSTERED INDEX IX_ShipmentId ON [dbo].[ShipmentItem] (ShipmentId ASC)

	PRINT 'Enabling Foreign key constrains'
	ALTER TABLE [dbo].[OrderForm] WITH CHECK CHECK CONSTRAINT [FK_dbo.OrderForm_dbo.OrderGroup_OrderGroupId]
	ALTER TABLE [dbo].[LineItem] WITH CHECK CHECK CONSTRAINT [FK_dbo.LineItem_dbo.OrderForm_OrderFormId]
	ALTER TABLE [dbo].[Shipment] WITH CHECK CHECK CONSTRAINT [FK_dbo.Shipment_dbo.OrderForm_OrderFormId]
	ALTER TABLE [dbo].[Shipment] WITH CHECK CHECK CONSTRAINT [FK_dbo.Shipment_dbo.Picklist_PicklistId]
	ALTER TABLE [dbo].[ShipmentItem] WITH CHECK CHECK CONSTRAINT [FK_dbo.ShipmentItem_dbo.LineItem_LineItemId]
	ALTER TABLE [dbo].[ShipmentItem] WITH CHECK CHECK CONSTRAINT [FK_dbo.ShipmentItem_dbo.Shipment_ShipmentId]

	END
END