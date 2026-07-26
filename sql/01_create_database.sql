/*
  База данных для учебного WEB-приложения HelpDeskWeb.
  СУБД: Microsoft SQL Server.
  Скрипт можно выполнять повторно: существующие учебные таблицы будут пересозданы.
*/

USE [master];
GO

IF DB_ID(N'HelpDeskWebDB') IS NULL
BEGIN
  CREATE DATABASE [HelpDeskWebDB];
END;
GO

USE [HelpDeskWebDB];
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.ServiceRequests', N'U') IS NOT NULL
  DROP TABLE dbo.ServiceRequests;
GO

IF OBJECT_ID(N'dbo.RequestStatuses', N'U') IS NOT NULL
  DROP TABLE dbo.RequestStatuses;
GO

IF OBJECT_ID(N'dbo.Departments', N'U') IS NOT NULL
  DROP TABLE dbo.Departments;
GO

CREATE TABLE dbo.Departments
(
  DepartmentID   INT IDENTITY(1,1) NOT NULL,
  DepartmentName NVARCHAR(100) NOT NULL,
  CONSTRAINT PK_Departments PRIMARY KEY (DepartmentID),
  CONSTRAINT UQ_Departments_DepartmentName UNIQUE (DepartmentName)
);
GO

CREATE TABLE dbo.RequestStatuses
(
  StatusID   INT IDENTITY(1,1) NOT NULL,
  StatusName NVARCHAR(50) NOT NULL,
  CONSTRAINT PK_RequestStatuses PRIMARY KEY (StatusID),
  CONSTRAINT UQ_RequestStatuses_StatusName UNIQUE (StatusName)
);
GO

CREATE TABLE dbo.ServiceRequests
(
  RequestID    INT IDENTITY(1,1) NOT NULL,
  DepartmentID INT NOT NULL,
  StatusID     INT NOT NULL CONSTRAINT DF_ServiceRequests_StatusID DEFAULT (1),
  EmployeeName NVARCHAR(100) NOT NULL,
  Subject      NVARCHAR(150) NOT NULL,
  Description  NVARCHAR(1000) NOT NULL,
  CreatedAt    DATETIME2(0) NOT NULL CONSTRAINT DF_ServiceRequests_CreatedAt DEFAULT (SYSDATETIME()),
  CONSTRAINT PK_ServiceRequests PRIMARY KEY (RequestID),
  CONSTRAINT CK_ServiceRequests_EmployeeName_NotBlank
    CHECK (LEN(LTRIM(RTRIM(EmployeeName))) > 0),
  CONSTRAINT CK_ServiceRequests_Subject_NotBlank
    CHECK (LEN(LTRIM(RTRIM(Subject))) > 0),
  CONSTRAINT CK_ServiceRequests_Description_NotBlank
    CHECK (LEN(LTRIM(RTRIM(Description))) > 0),
  CONSTRAINT FK_ServiceRequests_Departments
    FOREIGN KEY (DepartmentID) REFERENCES dbo.Departments (DepartmentID),
  CONSTRAINT FK_ServiceRequests_RequestStatuses
    FOREIGN KEY (StatusID) REFERENCES dbo.RequestStatuses (StatusID)
);
GO

CREATE INDEX IX_ServiceRequests_DepartmentID
  ON dbo.ServiceRequests (DepartmentID);
GO

CREATE INDEX IX_ServiceRequests_StatusID
  ON dbo.ServiceRequests (StatusID);
GO

INSERT INTO dbo.Departments (DepartmentName)
VALUES
  (N'Бухгалтерия'),
  (N'Кадровая служба'),
  (N'Отдел продаж');
GO

INSERT INTO dbo.RequestStatuses (StatusName)
VALUES
  (N'Новая'),
  (N'В работе'),
  (N'Выполнена');
GO

INSERT INTO dbo.ServiceRequests
  (DepartmentID, StatusID, EmployeeName, Subject, Description)
VALUES
  (1, 1, N'Иванова Анна', N'Не печатает принтер',
   N'После включения принтер отображается в системе, но документ не выводится на печать.'),
  (3, 2, N'Петров Сергей', N'Нет доступа к общей папке',
   N'При открытии сетевой папки появляется сообщение об отсутствии прав доступа.');
GO

SELECT N'База HelpDeskWebDB успешно создана.' AS Result;
GO
