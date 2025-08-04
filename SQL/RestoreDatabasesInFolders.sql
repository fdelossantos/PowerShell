-- Script T-SQL para restaurar respaldos de SQL Server
-- NOTA: Este script requiere que hayas obtenido manualmente la lista de archivos .bak
-- y que ajustes los nombres de archivo para cada base de datos

-- Variables de configuración
DECLARE @BackupFolder NVARCHAR(500) = 'E:\Work\Backup\'
DECLARE @DataPath NVARCHAR(500) = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\'
DECLARE @LogPath NVARCHAR(500) = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\'
DECLARE @BackupFile NVARCHAR(500)
DECLARE @DatabaseName NVARCHAR(128)
DECLARE @NewDatabaseName NVARCHAR(128)
DECLARE @RestoreCommand NVARCHAR(MAX)
DECLARE @FileListCommand NVARCHAR(MAX)
DECLARE @LogicalDataName NVARCHAR(128)
DECLARE @LogicalLogName NVARCHAR(128)

-- Tabla temporal para almacenar información de archivos del respaldo
CREATE TABLE #FileList (
    LogicalName NVARCHAR(128),
    PhysicalName NVARCHAR(260),
    Type CHAR(1),
    FileGroupName NVARCHAR(128),
    Size NUMERIC(20,0),
    MaxSize NUMERIC(20,0),
    FileID BIGINT,
    CreateLSN NUMERIC(25,0),
    DropLSN NUMERIC(25,0),
    UniqueID UNIQUEIDENTIFIER,
    ReadOnlyLSN NUMERIC(25,0),
    ReadWriteLSN NUMERIC(25,0),
    BackupSizeInBytes BIGINT,
    SourceBlockSize INT,
    FileGroupID INT,
    LogGroupGUID UNIQUEIDENTIFIER,
    DifferentialBaseLSN NUMERIC(25,0),
    DifferentialBaseGUID UNIQUEIDENTIFIER,
    IsReadOnly BIT,
    IsPresent BIT,
    TDEThumbprint VARBINARY(32),
    SnapshotURL NVARCHAR(360)
)

-- Tabla temporal para almacenar la lista de archivos de respaldo
-- DEBES LLENAR ESTA TABLA MANUALMENTE con los archivos .bak que quieres restaurar
CREATE TABLE #BackupFiles (
    ID INT IDENTITY(1,1),
    BackupFileName NVARCHAR(500),
    OriginalDatabaseName NVARCHAR(128)
)

-- LLENAR MANUALMENTE LA TABLA CON LOS ARCHIVOS DE RESPALDO
-- Ejemplo de cómo llenar la tabla:
INSERT INTO #BackupFiles (BackupFileName, OriginalDatabaseName) VALUES 
('archivo1.bak', 'base1'),
('archivo2.bak', 'base2'),
('archivo3.bak', 'base3')
-- Agregar más archivos según sea necesario

PRINT 'Iniciando proceso de restauración de respaldos...'
PRINT 'Carpeta de respaldos: ' + @BackupFolder
PRINT 'Carpeta de datos: ' + @DataPath
PRINT 'Carpeta de logs: ' + @LogPath
PRINT '========================================'

DECLARE backup_cursor CURSOR FOR
SELECT BackupFileName, OriginalDatabaseName 
FROM #BackupFiles

OPEN backup_cursor
FETCH NEXT FROM backup_cursor INTO @BackupFile, @DatabaseName

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        -- Construir ruta completa del archivo de respaldo
        SET @BackupFile = @BackupFolder + @BackupFile
        SET @NewDatabaseName = @DatabaseName + '_Restored'
        
        PRINT 'Procesando: ' + @BackupFile
        PRINT 'Base de datos original: ' + @DatabaseName
        PRINT 'Nueva base de datos: ' + @NewDatabaseName
        
        -- Verificar si la base de datos ya existe
        IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @NewDatabaseName)
        BEGIN
            PRINT 'La base de datos ' + @NewDatabaseName + ' ya existe. Saltando...'
            GOTO NextBackup
        END
        
        -- Limpiar tabla temporal
        DELETE FROM #FileList
        
        -- Obtener lista de archivos del respaldo
        SET @FileListCommand = 'RESTORE FILELISTONLY FROM DISK = ''' + @BackupFile + ''''
        INSERT INTO #FileList 
        EXEC sp_executesql @FileListCommand
        
        -- Obtener nombres lógicos de archivos de datos y log
        SELECT @LogicalDataName = LogicalName FROM #FileList WHERE Type = 'D'
        SELECT @LogicalLogName = LogicalName FROM #FileList WHERE Type = 'L'
        
        PRINT 'Archivo de datos lógico: ' + ISNULL(@LogicalDataName, 'N/A')
        PRINT 'Archivo de log lógico: ' + ISNULL(@LogicalLogName, 'N/A')
        
        -- Construir comando de restauración
        SET @RestoreCommand = 'RESTORE DATABASE [' + @NewDatabaseName + '] 
FROM DISK = ''' + @BackupFile + ''' 
WITH 
    MOVE ''' + @LogicalDataName + ''' TO ''' + @DataPath + @NewDatabaseName + '_Data.mdf'',
    MOVE ''' + @LogicalLogName + ''' TO ''' + @LogPath + @NewDatabaseName + '_Log.ldf'',
    REPLACE,
    RECOVERY,
    STATS = 10'
        
        PRINT 'Ejecutando restauración...'
        PRINT @RestoreCommand
        
        -- Ejecutar restauración
        EXEC sp_executesql @RestoreCommand
        
        PRINT '✓ Restauración exitosa: ' + @NewDatabaseName
        
    END TRY
    BEGIN CATCH
        PRINT '✗ Error al restaurar ' + @DatabaseName + ': ' + ERROR_MESSAGE()
    END CATCH
    
    NextBackup:
    PRINT '----------------------------------------'
    
    FETCH NEXT FROM backup_cursor INTO @BackupFile, @DatabaseName
END

CLOSE backup_cursor
DEALLOCATE backup_cursor

-- Limpiar tablas temporales
DROP TABLE #FileList
DROP TABLE #BackupFiles

PRINT 'Proceso de restauración completado.'

-- Mostrar bases de datos restauradas
PRINT ''
PRINT 'Bases de datos restauradas:'
SELECT name AS 'Base de Datos Restaurada'
FROM sys.databases 
WHERE name LIKE '%_Restored'
ORDER BY name