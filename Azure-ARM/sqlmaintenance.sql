CREATE OR ALTER PROCEDURE [AzureSQLMaintenance]
	(
		@operation nvarchar(10) = null,
		@mode nvarchar(10) = 'smart',
		@ResumableIndexRebuild bit = 0,
		@RebuildHeaps bit = 0,
		@LogToTable bit = 0,
		@debug nvarchar(10) = 'off'
	)
as
begin
	set nocount on;
	
	set quoted_identifier on;
	declare @idxIdentifierBegin char(1), @idxIdentifierEnd char(1);
	declare @statsIdentifierBegin char(1), @statsIdentifierEnd char(1);
	
	declare @msg nvarchar(max);
	declare @minPageCountForIndex int = 40;
	declare @OperationTime datetime2 = sysdatetime();
	declare @KeepXOperationInLog int =3;
	declare @ScriptHasAnError int = 0; 
	declare @ResumableIndexRebuildSupported int;
	declare @indexStatsMode sysname;
	declare @LowFragmentationBoundry int = 5;
	declare @HighFragmentationBoundry int = 30;

	set @operation = lower(@operation)
	set @mode = lower(@mode)
	set @debug = lower(@debug) 
	
	if @mode not in ('smart','dummy')
		set @mode = 'smart'

	if @operation not in ('index','statistics','all') or @operation is null
	begin
		raiserror('@operation (varchar(10)) [mandatory]',0,0)
		raiserror(' Select operation to perform:',0,0)
		raiserror('     "index" to perform index maintenance',0,0)
		raiserror('     "statistics" to perform statistics maintenance',0,0)
		raiserror('     "all" to perform indexes and statistics maintenance',0,0)
		raiserror(' ',0,0)
		raiserror('@mode(varchar(10)) [optional]',0,0)
		raiserror(' optionaly you can supply second parameter for operation mode: ',0,0)
		raiserror('     "smart" (Default) using smart decision about what index or stats should be touched.',0,0)
		raiserror('     "dummy" going through all indexes and statistics regardless thier modifications or fragmentation.',0,0)
		raiserror(' ',0,0)
		raiserror('@ResumableIndexRebuild(bit) [optional]',0,0)
		raiserror(' Optionaly you can choose to rebuild indexes as resumable operation: ',0,0)
		raiserror('     "0" (Default) using non resumable index rebuild.',0,0)
		raiserror('     "1" using resumable index rebuild when it is supported.',0,0)
		raiserror(' ',0,0)
		raiserror('@RebuildHeaps(bit) [optional]',0,0)
		raiserror(' Rebuild HEAPS to fix forwarded records issue on tables with no clustered index',0,0)
		raiserror('     0 - (Default) do not rebuild heaps',0,0)
		raiserror('     1 - Rebuild heaps based on @mode parameter, @mode=dummy will rebuild all heaps',0,0)
		raiserror(' ',0,0)
		raiserror('@LogToTable(bit) [optional]',0,0)
		raiserror(' Optionaly allows you to turn on logging ',0,0)
		raiserror('     0 - (Default) do not log operation to table',0,0)
		raiserror('     1 - log operation to table',0,0)
		raiserror('		for logging option only 3 last execution will be kept by default. this can be changed by easily in the procedure body.',0,0)
		raiserror('		Log table will be created automatically if not exists.',0,0)
		raiserror(' ',0,0)
		raiserror('@debug [optional]',0,0)
		raiserror(' Allows debugging feature.',0,0)
		raiserror('     off - (Default) debug option is off',0,0)
		raiserror('     whatif - Remark all commands so it will not be executed, helps with understanding the commands to be executed',0,0)
		raiserror('     * in any case debug is used there will be user tables created to help with reviewing the process. cmdQueue, idxBefore and statsBefore ',0,0)
		raiserror(' ',0,0)
		raiserror('Example:',0,0)
		raiserror('		exec  AzureSQLMaintenance ''all'', @LogToTable=1',0,0)
	end
	else 
	begin
		
		if object_id('AzureSQLMaintenanceLog') is null and @LogToTable=1
		begin
			create table AzureSQLMaintenanceLog (id bigint primary key identity(1,1), OperationTime datetime2, command varchar(4000),ExtraInfo varchar(4000), StartTime datetime2, EndTime datetime2, StatusMessage varchar(1000));
		end

		if OBJECT_ID('AzureSQLMaintenanceCMDQueue') is not null 
		begin
			if 
				exists(select * from AzureSQLMaintenanceCMDQueue where ID=-1) 
			begin
				set @operation='resume'

				select top 1
				@LogToTable = JSON_VALUE(ExtraInfo,'$.LogToTable')
				,@mode = JSON_VALUE(ExtraInfo,'$.mode')
				,@ResumableIndexRebuild = JSON_VALUE(ExtraInfo,'$.ResumableIndexRebuild')
				from AzureSQLMaintenanceCMDQueue 
				where ID=-1
				
				raiserror('-----------------------',0,0)
				set @msg = 'Resuming previous operation'
				raiserror(@msg,0,0)
				raiserror('-----------------------',0,0)
			end
			else
				begin
					DROP TABLE [AzureSQLMaintenanceCMDQueue];
				end
		end


		
		raiserror('-----------------------',0,0)
		set @msg = 'set operation = ' + @operation;
		raiserror(@msg,0,0)
		set @msg = 'set mode = ' + @mode;
		raiserror(@msg,0,0)
		set @msg = 'set ResumableIndexRebuild = ' + cast(@ResumableIndexRebuild as varchar(1));
		raiserror(@msg,0,0)
		set @msg = 'set RebuildHeaps = ' + cast(@RebuildHeaps as varchar(1));
		raiserror(@msg,0,0)
		set @msg = 'set LogToTable = ' + cast(@LogToTable as varchar(1));
		raiserror(@msg,0,0)
		set @msg = 'set debug = ' + @debug;
		raiserror(@msg,0,0)
		raiserror('-----------------------',0,0)
	end

	if @LogToTable=1 insert into AzureSQLMaintenanceLog values(@OperationTime,null,null,sysdatetime(),sysdatetime(),'Starting operation: Operation=' +@operation + ' Mode=' + @mode + ' Keep log for last ' + cast(@KeepXOperationInLog as varchar(10)) + ' operations' )	

	if @operation!='resume'
		create table AzureSQLMaintenanceCMDQueue (ID int identity primary key,txtCMD nvarchar(max),ExtraInfo varchar(max))


	if @ResumableIndexRebuild=1 
	begin
		if cast(SERVERPROPERTY('EngineEdition')as int)>=5 or cast(SERVERPROPERTY('ProductMajorVersion')as int)>=14
		begin
			set @ResumableIndexRebuildSupported=1;
		end
		else
		begin 
				set @ResumableIndexRebuildSupported=0;
				set @msg = 'Resumable index rebuild is not supported on this database'
				raiserror(@msg,0,0)
				if @LogToTable=1 insert into AzureSQLMaintenanceLog values(@OperationTime,null,null,sysdatetime(),sysdatetime(),@msg)	
		end
	end



	if @operation in('index','all')
	begin
		if @mode='smart' and @RebuildHeaps=1 
			set @indexStatsMode = 'SAMPLED'
		else
			set @indexStatsMode = 'LIMITED'
	
		raiserror('Get index information...(wait)',0,0) with nowait;
		select 
			idxs.[object_id]
			,ObjectSchema = OBJECT_SCHEMA_NAME(idxs.object_id)
			,ObjectName = object_name(idxs.object_id) 
			,IndexName = idxs.name
			,idxs.type
			,idxs.type_desc
			,i.avg_fragmentation_in_percent
			,i.page_count
			,i.index_id
			,i.partition_number
			,i.avg_page_space_used_in_percent
			,i.record_count
			,i.ghost_record_count
			,i.forwarded_record_count
			,null as OnlineOpIsNotSupported
			,null as ObjectDoesNotSupportResumableOperation
			,case when ps.data_space_id IS NULL then 0 else 1 end as IsPartitioned
			,0 as SkipIndex
			,replicate(' ',20)  as OperationToTake 
			,replicate(' ',128) as SkipReason
		into #idxBefore
		from sys.indexes idxs 
		left join sys.partition_schemes ps ON idxs.data_space_id = ps.data_space_id
		inner join sys.objects obj on idxs.object_id = obj.object_id
		inner join sys.dm_db_index_physical_stats(DB_ID(),NULL, NULL, NULL ,@indexStatsMode) i  on i.object_id = idxs.object_id and i.index_id = idxs.index_id
		where idxs.type in (0 /*HEAP*/,1/*CLUSTERED*/,2/*NONCLUSTERED*/,5,6) 
		and (alloc_unit_type_desc = 'IN_ROW_DATA' /*avoid LOB_DATA or ROW_OVERFLOW_DATA*/ or alloc_unit_type_desc is null )
		and OBJECT_SCHEMA_NAME(idxs.object_id) != 'sys'
		and idxs.is_disabled=0
		and obj.type_desc != 'TF' 
		order by i.avg_fragmentation_in_percent desc, i.page_count desc
				

		update #idxBefore set OnlineOpIsNotSupported=1 where [object_id] in (select [object_id] from #idxBefore where [type]=3 /*XML Indexes*/)


		update #idxBefore set OnlineOpIsNotSupported=1 
		where index_id=1 /*clustered*/ and [object_id] in (
			select object_id
			from sys.columns c join sys.types t on c.user_type_id = t.user_type_id
			where t.name in ('text','ntext','image')
		)
	

		update #idxBefore set OnlineOpIsNotSupported=1  
			where
				convert(varchar(100),serverproperty('Edition')) like '%Express%' 
				or convert(varchar(100),serverproperty('Edition')) like '%Standard%'
				or convert(varchar(100),serverproperty('Edition')) like '%Web%'

		update idx set ObjectDoesNotSupportResumableOperation=1
		from #idxBefore idx join sys.index_columns ic on idx.object_id = ic.object_id and idx.index_id=ic.index_id
		join sys.columns c on ic.object_id=c.object_id and ic.column_id=c.column_id
		where c.is_computed=1 or system_type_id=189 /*TimeStamp column*/
		

		update #idxBefore set SkipIndex=1,SkipReason='Maintenance is not needed as table is too small'
		where (
					(page_count<=@minPageCountForIndex)
				)
				and @mode != 'dummy' /*for Dummy mode we do not want to skip anything */
		
		update #idxBefore set SkipIndex=1,SkipReason='Maintenance is not needed as fragmentation % is low'
		where (
					(page_count>@minPageCountForIndex and avg_fragmentation_in_percent<@LowFragmentationBoundry)
				)
				and @mode != 'dummy' /*for Dummy mode we do not want to skip anything */
		
		update #idxBefore set SkipIndex=1,SkipReason='Columnstore index'
		where (
					type in (
								5/*Clustered columnstore index*/,
								6/*Nonclustered columnstore index*/
							)
				)
				and @mode != 'dummy' /*for Dummy mode we do not want to skip anything */

		/***/
		update #idxBefore set OperationToTake = 
			case when
			(
				avg_fragmentation_in_percent between @LowFragmentationBoundry and @HighFragmentationBoundry and @mode = 'smart')/* index fragmentation condition */ 
				or 
				(@mode='dummy' and type in (5,6))/* Columnstore indexes in dummy mode -> reorganize them */
			then
				 'REORGANIZE'
			else 
				'REBUILD'
			end

		raiserror('---------------------------------------',0,0) with nowait
		raiserror('Index Information:',0,0) with nowait
		raiserror('---------------------------------------',0,0) with nowait

		select @msg = count(*) from #idxBefore 
		set @msg = 'Total Indexes: ' + @msg
		raiserror(@msg,0,0) with nowait

		select @msg = avg(avg_fragmentation_in_percent) from #idxBefore where page_count>@minPageCountForIndex
		set @msg = 'Average Fragmentation: ' + @msg
		raiserror(@msg,0,0) with nowait

		select @msg = sum(iif(avg_fragmentation_in_percent>=@LowFragmentationBoundry and page_count>@minPageCountForIndex,1,0)) from #idxBefore 
		set @msg = 'Fragmented Indexes: ' + @msg
		raiserror(@msg,0,0) with nowait

				
		raiserror('---------------------------------------',0,0) with nowait

		if exists(
			select 1
			from #idxBefore 
			where IndexName like '%[%' or IndexName like '%]%'
			or ObjectSchema like '%[%' or ObjectSchema like '%]%'
			or ObjectName like '%[%' or ObjectName like '%]%'
			)
		begin
			set @idxIdentifierBegin = '"'
			set @idxIdentifierEnd = '"'
		end
		else 
		begin
			set @idxIdentifierBegin = '['
			set @idxIdentifierEnd = ']'
		end

			
		/* create queue for indexes */
		insert into AzureSQLMaintenanceCMDQueue(txtCMD,ExtraInfo)
		select 
		txtCMD = 'ALTER INDEX ' + @idxIdentifierBegin + IndexName + @idxIdentifierEnd + ' ON '+ @idxIdentifierBegin + ObjectSchema + @idxIdentifierEnd +'.'+ @idxIdentifierBegin + ObjectName + @idxIdentifierEnd + ' ' +
		OperationToTake+ ' ' + 
		case when IsPartitioned = 1 then 'PARTITION=' + CAST(partition_number AS varchar(10)) + ' ' else '' end +
		case 
			when OperationToTake = 'REBUILD' and OnlineOpIsNotSupported=1 then
			'WITH(ONLINE=OFF,MAXDOP=1)'
			when OperationToTake = 'REBUILD' and (ObjectDoesNotSupportResumableOperation=1 or @ResumableIndexRebuildSupported=0 or @ResumableIndexRebuild=0) then
			'WITH(ONLINE=ON,MAXDOP=1)'
			when OperationToTake = 'REBUILD' then
			'WITH(ONLINE=ON,MAXDOP=1, RESUMABLE=ON)'
			else 
			''
		end + ';'
		, ExtraInfo =
			'Taking Action: ' + OperationToTake + ' ' + 
			case when type in (5,6) then
				'Dummy mode therefore reorganize columnstore indexes'
			else 
				'Current fragmentation: ' + format(avg_fragmentation_in_percent/100,'p')+ ' with ' + cast(page_count as nvarchar(20)) + ' pages'
			end
		from #idxBefore
		where SkipIndex=0 and type != 0 /*Avoid HEAPS*/


		/* create queue for heaps */
		if @RebuildHeaps=1 
		begin
			insert into AzureSQLMaintenanceCMDQueue(txtCMD,ExtraInfo)
			select 
			txtCMD = 'ALTER TABLE ' + @idxIdentifierBegin + ObjectSchema + @idxIdentifierEnd +'.'+ @idxIdentifierBegin + ObjectName + @idxIdentifierEnd + ' REBUILD ' + 
			case when IsPartitioned = 1 then 'PARTITION=' + CAST(partition_number AS varchar(10)) + ' ' else '' end + ';' 
			, ExtraInfo = 'Rebuilding heap - forwarded records ' + cast(forwarded_record_count as varchar(100)) + ' out of ' + cast(record_count as varchar(100)) + ' record in the table'
			from #idxBefore
			where
				type = 0 /*heaps*/
				and 
					(
						@mode='dummy' 
						or 
						(forwarded_record_count/nullif(record_count,0)>0.3) /* 30% of record count */
						or
						(forwarded_record_count>105000) /* for tables with > 350K rows dont wait for 30%, just run yje maintenance once we reach the 100K forwarded records */
					)
		end /* create queue for heaps */
	end


	if @operation in('statistics','all')
	begin 
		/*Gets Stats for database*/
		raiserror('Get statistics information...',0,0) with nowait;
		select 
			ObjectSchema = OBJECT_SCHEMA_NAME(s.object_id)
			,ObjectName = object_name(s.object_id) 
			,s.object_id
			,s.stats_id
			,StatsName = s.name
			,sp.last_updated
			,sp.rows
			,sp.rows_sampled
			,sp.modification_counter
			, i.type
			, i.type_desc
			,0 as SkipStatistics
		into #statsBefore
		from sys.stats s cross apply sys.dm_db_stats_properties(s.object_id,s.stats_id) sp 
		left join sys.indexes i on sp.object_id = i.object_id and sp.stats_id = i.index_id
		where OBJECT_SCHEMA_NAME(s.object_id) != 'sys' and /*Modified stats or Dummy mode*/(isnull(sp.modification_counter,0)>0 or @mode='dummy')
		order by sp.last_updated asc

		if @operation= 'all'
		update _stats set SkipStatistics=1 
			from #statsBefore _stats
			join #idxBefore _idx
			on _idx.ObjectSchema = _stats.ObjectSchema
			and _idx.ObjectName = _stats.ObjectName
			and _idx.IndexName = _stats.StatsName 
			where _idx.SkipIndex=0 and _idx.OperationToTake='REBUILD'

		update #statsBefore set SkipStatistics=1
		where type in (5,6) /*Column store indexes*/

		if @ResumableIndexRebuildSupported=1
		begin
			update _stats set SkipStatistics=1
			from #statsBefore _stats join sys.index_resumable_operations iro on _stats.object_id=iro.object_id and _stats.stats_id=iro.index_id
		end
		
		raiserror('---------------------------------------',0,0) with nowait
		raiserror('Statistics Information:',0,0) with nowait
		raiserror('---------------------------------------',0,0) with nowait

		select @msg = sum(modification_counter) from #statsBefore
		set @msg = 'Total Modifications: ' + @msg
		raiserror(@msg,0,0) with nowait
		
		select @msg = sum(iif(modification_counter>0,1,0)) from #statsBefore
		set @msg = 'Modified Statistics: ' + @msg
		raiserror(@msg,0,0) with nowait
				
		raiserror('---------------------------------------',0,0) with nowait

		/* Choose the identifier to be used based on existing object name */
		if exists(
			select 1
			from #statsBefore 
			where StatsName like '%[%' or StatsName like '%]%'
			or ObjectSchema like '%[%' or ObjectSchema like '%]%'
			or ObjectName like '%[%' or ObjectName like '%]%'
			)
		begin
			set @statsIdentifierBegin = '"'
			set @statsIdentifierEnd = '"'
		end
		else 
		begin
			set @statsIdentifierBegin = '['
			set @statsIdentifierEnd = ']'
		end
		
		/* create queue for update stats */
		insert into AzureSQLMaintenanceCMDQueue(txtCMD,ExtraInfo)
		select 
		txtCMD = 'UPDATE STATISTICS '+ @statsIdentifierBegin + ObjectSchema + +@statsIdentifierEnd + '.'+@statsIdentifierBegin + ObjectName + @statsIdentifierEnd +' (' + @statsIdentifierBegin + StatsName + @statsIdentifierEnd + ') WITH FULLSCAN;'
		, ExtraInfo = '#rows:' + cast([rows] as varchar(100)) + ' #modifications:' + cast(modification_counter as varchar(100)) + ' modification percent: ' + format((1.0 * modification_counter/ rows ),'p')
		from #statsBefore
		where SkipStatistics=0;
	end

	if @operation in('statistics','index','all','resume')
	begin

		declare @SQLCMD nvarchar(max);
		declare @ID int;
		declare @ExtraInfo nvarchar(max);
	
		/*handle debug options*/
		if @debug!='off'
		begin
			
			/*When whatif is used remark all commands*/
			if @debug='whatif' 
			begin
				update AzureSQLMaintenanceCMDQueue set txtCMD = '--' + txtCMD
			end
			
			drop table if exists idxBefore
			drop table if exists statsBefore
			drop table if exists cmdQueue
			if object_id('tempdb..#idxBefore') is not null select * into idxBefore from #idxBefore
			if object_id('tempdb..#statsBefore') is not null select * into statsBefore from #statsBefore
			if object_id('AzureSQLMaintenanceCMDQueue') is not null select * into cmdQueue from AzureSQLMaintenanceCMDQueue
		end
		
		if @operation!='resume'
		begin
			set @ExtraInfo = (select top 1 LogToTable = @LogToTable, operation=@operation, operationTime=@OperationTime, mode=@mode, ResumableIndexRebuild = @ResumableIndexRebuild from sys.tables for JSON path, WITHOUT_ARRAY_WRAPPER)
			set identity_insert AzureSQLMaintenanceCMDQueue on
			insert into AzureSQLMaintenanceCMDQueue(ID,txtCMD,ExtraInfo) values(-1,'parameters to be used by resume code path',@ExtraInfo)
			set identity_insert AzureSQLMaintenanceCMDQueue off
		end
	
		SET ANSI_WARNINGS ON;

		raiserror('Start executing commands...',0,0) with nowait
		declare @T table(ID int, txtCMD nvarchar(max),ExtraInfo nvarchar(max));
		while exists(select * from AzureSQLMaintenanceCMDQueue where ID>0)
		begin
			update top (1) AzureSQLMaintenanceCMDQueue set txtCMD=txtCMD output deleted.* into @T where ID>0;
			select top (1) @ID = ID, @SQLCMD = txtCMD, @ExtraInfo=ExtraInfo from @T
			raiserror(@SQLCMD,0,0) with nowait
			if @LogToTable=1 insert into AzureSQLMaintenanceLog values(@OperationTime,@SQLCMD,@ExtraInfo,sysdatetime(),null,'Started')
			begin try
				exec(@SQLCMD)	
				if @LogToTable=1 update AzureSQLMaintenanceLog set EndTime = sysdatetime(), StatusMessage = 'Succeeded' where id=SCOPE_IDENTITY()
			end try
			begin catch
				set @ScriptHasAnError=1;
				set @msg = 'FAILED : ' + CAST(ERROR_NUMBER() AS VARCHAR(50)) + ERROR_MESSAGE();
				raiserror(@msg,0,0) with nowait
				if @LogToTable=1 update AzureSQLMaintenanceLog set EndTime = sysdatetime(), StatusMessage = @msg where id=SCOPE_IDENTITY()
			end catch
			delete from AzureSQLMaintenanceCMDQueue where ID = @ID;
			delete from @T
		end
		drop table AzureSQLMaintenanceCMDQueue;
	end
	
	if @LogToTable=1
	begin
		delete from AzureSQLMaintenanceLog 
		from 
			AzureSQLMaintenanceLog L join 
			(select distinct OperationTime from AzureSQLMaintenanceLog order by OperationTime desc offset @KeepXOperationInLog rows) F
				ON L.OperationTime = F.OperationTime
		insert into AzureSQLMaintenanceLog values(@OperationTime,null,cast(@@rowcount as varchar(100))+ ' rows purged from log table because number of operations to keep is set to: ' + cast( @KeepXOperationInLog as varchar(100)),sysdatetime(),sysdatetime(),'Cleanup Log Table')
	end

	if @ScriptHasAnError=0 	raiserror('Done',0,0)
	if @LogToTable=1 insert into AzureSQLMaintenanceLog values(@OperationTime,null,null,sysdatetime(),sysdatetime(),'End of operation')
	if @ScriptHasAnError=1 	raiserror('Script has errors - please review the log.',16,1)
end
print 'Create or Alter Stored Procedure Done'