/*
  Выполните этот скрипт ПОСЛЕ создания в IIS пула приложений HelpDeskWebPool.
  Скрипт выдаёт приложению минимальные права: чтение трёх таблиц и
  добавление заявок. UPDATE, DELETE и права владельца базы не выдаются.
*/

USE [master];
GO

IF NOT EXISTS
(
  SELECT 1
  FROM sys.server_principals
  WHERE name = N'IIS APPPOOL\HelpDeskWebPool'
)
BEGIN
  CREATE LOGIN [IIS APPPOOL\HelpDeskWebPool] FROM WINDOWS;
END;
GO

USE [HelpDeskWebDB];
GO

IF NOT EXISTS
(
  SELECT 1
  FROM sys.database_principals
  WHERE name = N'IIS APPPOOL\HelpDeskWebPool'
)
BEGIN
  CREATE USER [IIS APPPOOL\HelpDeskWebPool]
    FOR LOGIN [IIS APPPOOL\HelpDeskWebPool];
END;
GO

-- Удаляем слишком широкие роли, если выполняется обновление ранней версии скрипта.
IF IS_ROLEMEMBER(N'db_datareader', N'IIS APPPOOL\HelpDeskWebPool') = 1
  ALTER ROLE db_datareader DROP MEMBER [IIS APPPOOL\HelpDeskWebPool];

IF IS_ROLEMEMBER(N'db_datawriter', N'IIS APPPOOL\HelpDeskWebPool') = 1
  ALTER ROLE db_datawriter DROP MEMBER [IIS APPPOOL\HelpDeskWebPool];

GRANT SELECT ON dbo.Departments TO [IIS APPPOOL\HelpDeskWebPool];
GRANT SELECT ON dbo.RequestStatuses TO [IIS APPPOOL\HelpDeskWebPool];
GRANT SELECT, INSERT ON dbo.ServiceRequests TO [IIS APPPOOL\HelpDeskWebPool];
GO

SELECT N'Доступ IIS к HelpDeskWebDB настроен.' AS Result;
GO
