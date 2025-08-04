-- Script para realizar respaldo COPY_ONLY de todas las bases de datos de usuario
-- Carpeta destino: \\SERVER-04\MigBackups

DECLARE @DatabaseName NVARCHAR(128)
DECLARE @BackupPath NVARCHAR(500)
DECLARE @BackupCommand NVARCHAR(1000)
DECLARE @Timestamp NVARCHAR(20)

-- Generar timestamp para los archivos de respaldo
SET @Timestamp = FORMAT(GETDATE(), 'yyyyMMdd_HHmmss')

-- Cursor para recorrer todas las bases de datos de usuario
DECLARE db_cursor CURSOR FOR
SELECT name 
FROM sys.databases 
WHERE database_id > 4  -- Excluye bases de datos del sistema (master, model, msdb, tempdb)
  AND state = 0        -- Solo bases de datos en línea
  AND name NOT IN ('ReportServer', 'ReportServerTempDB')  -- Opcional: excluir bases de Reporting Services

OPEN db_cursor
FETCH NEXT FROM db_cursor INTO @DatabaseName

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Construir la ruta completa del archivo de respaldo
    SET @BackupPath = '\\SERVER01\MigBackups\' + @DatabaseName + '_CopyOnly_' + @Timestamp + '.bak'
    
    -- Construir el comando de respaldo
    SET @BackupCommand = 'BACKUP DATABASE [' + @DatabaseName + '] 
                         TO DISK = ''' + @BackupPath + ''' 
                         WITH COPY_ONLY, 
                              COMPRESSION, 
                              CHECKSUM, 
                              INIT,
                              FORMAT,
                              NAME = ''' + @DatabaseName + ' Copy-Only Backup ' + @Timestamp + ''''
    
    -- Mostrar el comando que se va a ejecutar
    PRINT 'Ejecutando: ' + @BackupCommand
    PRINT ''
    
    BEGIN TRY
        -- Ejecutar el comando de respaldo
        EXEC sp_executesql @BackupCommand
        PRINT 'Respaldo exitoso de: ' + @DatabaseName
        PRINT 'Ubicación: ' + @BackupPath
    END TRY
    BEGIN CATCH
        -- Manejo de errores
        PRINT 'ERROR al respaldar ' + @DatabaseName + ': ' + ERROR_MESSAGE()
    END CATCH
    
    PRINT '----------------------------------------'
    
    -- Obtener siguiente base de datos
    FETCH NEXT FROM db_cursor INTO @DatabaseName
END

-- Limpiar cursor
CLOSE db_cursor
DEALLOCATE db_cursor

PRINT 'Proceso de respaldo completado.'
PRINT 'Timestamp utilizado: ' + @Timestamp