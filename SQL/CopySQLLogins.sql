-- Logins SQL (excluye sistemas y Windows logins)
SELECT
  'CREATE LOGIN [' + sp.name + '] WITH ' +
  'PASSWORD = ' + CONVERT(varchar(max), sl.password_hash, 1) + ' HASHED, ' +
  'SID = ' + CONVERT(varchar(max), sp.sid, 1) + ', ' +
  'DEFAULT_DATABASE = [' + sl.default_database_name + '], ' +
  'DEFAULT_LANGUAGE = [' + sl.default_language_name + '], ' +
  'CHECK_POLICY = ' + CASE WHEN sl.is_policy_checked = 1 THEN 'ON' ELSE 'OFF' END + ', ' +
  'CHECK_EXPIRATION = ' + CASE WHEN sl.is_expiration_checked = 1 THEN 'ON' ELSE 'OFF' END + ';' +
  CASE WHEN sp.is_disabled = 1 THEN CHAR(13) + 'ALTER LOGIN [' + sp.name + '] DISABLE;' ELSE '' END
AS [-- Run on target]
FROM sys.sql_logins sl
JOIN sys.server_principals sp ON sl.principal_id = sp.principal_id
WHERE sp.type = 'S'               -- SQL logins
  AND sp.name NOT IN ('sa')       -- ajusta a gusto
  AND sp.is_disabled IN (0,1);

-- Membresías a roles de servidor (ejecutar después de crear los logins)
SELECT
  'EXEC sp_addsrvrolemember @loginame = N''' + m.name + ''', @rolename = N''' + r.name + ''';'
AS [-- Run on target]
FROM sys.server_role_members srm
JOIN sys.server_principals r ON r.principal_id = srm.role_principal_id
JOIN sys.server_principals m ON m.principal_id = srm.member_principal_id
WHERE m.type IN ('S','U');        -- SQL y Windows logins
