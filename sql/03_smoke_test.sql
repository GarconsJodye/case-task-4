/*
  Проверка структуры и базовых операций.
  Тестовая строка откатывается. Как обычно для SQL Server IDENTITY,
  после ROLLBACK в последовательности номеров возможен пропуск.
*/

USE [HelpDeskWebDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.Departments', N'U') IS NULL
BEGIN
  ;THROW 51000, N'Не найдена таблица dbo.Departments.', 1;
END;

IF OBJECT_ID(N'dbo.RequestStatuses', N'U') IS NULL
BEGIN
  ;THROW 51000, N'Не найдена таблица dbo.RequestStatuses.', 1;
END;

IF OBJECT_ID(N'dbo.ServiceRequests', N'U') IS NULL
BEGIN
  ;THROW 51000, N'Не найдена таблица dbo.ServiceRequests.', 1;
END;

IF (SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID(N'dbo.ServiceRequests')) <> 2
BEGIN
  ;THROW 51000, N'В таблице dbo.ServiceRequests должно быть два внешних ключа.', 1;
END;

IF (SELECT COUNT(*) FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID(N'dbo.ServiceRequests')) <> 3
BEGIN
  ;THROW 51000, N'В таблице dbo.ServiceRequests должно быть три CHECK-ограничения.', 1;
END;

IF ISNULL(COL_LENGTH(N'dbo.ServiceRequests', N'EmployeeName'), -1) <> 200
   OR ISNULL(COL_LENGTH(N'dbo.ServiceRequests', N'Subject'), -1) <> 300
   OR ISNULL(COL_LENGTH(N'dbo.ServiceRequests', N'Description'), -1) <> 2000
BEGIN
  ;THROW 51000, N'Длины NVARCHAR-полей не соответствуют схеме.', 1;
END;

IF NOT EXISTS
(
  SELECT 1
  FROM sys.indexes
  WHERE object_id = OBJECT_ID(N'dbo.ServiceRequests')
    AND name = N'IX_ServiceRequests_DepartmentID'
)
BEGIN
  ;THROW 51000, N'Не найден индекс по DepartmentID.', 1;
END;

IF NOT EXISTS
(
  SELECT 1
  FROM sys.indexes
  WHERE object_id = OBJECT_ID(N'dbo.ServiceRequests')
    AND name = N'IX_ServiceRequests_StatusID'
)
BEGIN
  ;THROW 51000, N'Не найден индекс по StatusID.', 1;
END;

IF NOT EXISTS (SELECT 1 FROM dbo.Departments)
BEGIN
  ;THROW 51000, N'Справочник подразделений пуст.', 1;
END;

IF NOT EXISTS (SELECT 1 FROM dbo.RequestStatuses WHERE StatusID = 1)
BEGIN
  ;THROW 51000, N'Не найден начальный статус с StatusID = 1.', 1;
END;

DECLARE @BeforeCount INT = (SELECT COUNT(*) FROM dbo.ServiceRequests);

BEGIN TRANSACTION;

INSERT INTO dbo.ServiceRequests
  (DepartmentID, StatusID, EmployeeName, Subject, Description)
VALUES
  ((SELECT MIN(DepartmentID) FROM dbo.Departments),
   1,
   N'Тестовый пользователь',
   N'Проверка добавления',
   N'Эта запись создаётся только внутри smoke-теста.');

IF (SELECT COUNT(*) FROM dbo.ServiceRequests) <> @BeforeCount + 1
BEGIN
  ROLLBACK TRANSACTION;
  ;THROW 51000, N'Тестовая заявка не была добавлена.', 1;
END;

ROLLBACK TRANSACTION;

IF (SELECT COUNT(*) FROM dbo.ServiceRequests) <> @BeforeCount
BEGIN
  ;THROW 51000, N'После ROLLBACK изменилась таблица dbo.ServiceRequests.', 1;
END;

SELECT N'SMOKE TEST PASSED' AS Result;
GO
