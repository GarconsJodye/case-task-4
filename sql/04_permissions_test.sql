/*
  Запускается после 02_grant_iis_access.sql.
  Проверяет эффективные права пользователя пула IIS без изменения данных.
*/

USE [HelpDeskWebDB];
GO

SET NOCOUNT ON;
GO

IF USER_ID(N'IIS APPPOOL\HelpDeskWebPool') IS NULL
BEGIN
  ;THROW 51000, N'Не найден пользователь IIS APPPOOL\HelpDeskWebPool.', 1;
END;

DECLARE @CanReadDepartments INT;
DECLARE @CanReadStatuses INT;
DECLARE @CanReadRequests INT;
DECLARE @CanInsertRequests INT;
DECLARE @CanUpdateRequests INT;
DECLARE @CanDeleteRequests INT;
DECLARE @CanControlDatabase INT;

EXECUTE AS USER = N'IIS APPPOOL\HelpDeskWebPool';

SELECT
  @CanReadDepartments = HAS_PERMS_BY_NAME(N'dbo.Departments', N'OBJECT', N'SELECT'),
  @CanReadStatuses = HAS_PERMS_BY_NAME(N'dbo.RequestStatuses', N'OBJECT', N'SELECT'),
  @CanReadRequests = HAS_PERMS_BY_NAME(N'dbo.ServiceRequests', N'OBJECT', N'SELECT'),
  @CanInsertRequests = HAS_PERMS_BY_NAME(N'dbo.ServiceRequests', N'OBJECT', N'INSERT'),
  @CanUpdateRequests = HAS_PERMS_BY_NAME(N'dbo.ServiceRequests', N'OBJECT', N'UPDATE'),
  @CanDeleteRequests = HAS_PERMS_BY_NAME(N'dbo.ServiceRequests', N'OBJECT', N'DELETE'),
  @CanControlDatabase = HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CONTROL');

REVERT;

IF ISNULL(@CanReadDepartments, 0) <> 1
   OR ISNULL(@CanReadStatuses, 0) <> 1
   OR ISNULL(@CanReadRequests, 0) <> 1
   OR ISNULL(@CanInsertRequests, 0) <> 1
BEGIN
  ;THROW 51000, N'Пулу IIS не хватает прав SELECT или INSERT.', 1;
END;

IF ISNULL(@CanUpdateRequests, 1) <> 0
   OR ISNULL(@CanDeleteRequests, 1) <> 0
   OR ISNULL(@CanControlDatabase, 1) <> 0
BEGIN
  ;THROW 51000, N'Пулу IIS выданы избыточные права.', 1;
END;

SELECT N'PERMISSIONS TEST PASSED' AS Result;
GO
