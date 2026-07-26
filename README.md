# Кейс-задача № 4 — Delphi 10.2, IIS и MS SQL Server

Учебное WEB-приложение **HelpDeskWeb** предназначено для регистрации заявок сотрудников в IT-службу.

## Соответствие исходному заданию

- выполнен анализ существующих информационных систем WEB-архитектуры;
- описаны возможности систем и варианты их применения в компании;
- приложение создано на Delphi 10.2 WebBroker как ISAPI DLL;
- для размещения используется Microsoft IIS;
- база данных создана в Microsoft SQL Server;
- SQL-схема экспортирована в отдельный скрипт;
- исходный код подготовлен для размещения в GitHub.

Упоминание MySQL в последнем пункте исходного задания является общим примером экспорта схемы. В практической части используется именно **MS SQL Server**, как прямо требуется в основном условии.

## Возможности приложения

Приложение выполняет необходимые учебные операции:

1. показывает последние 200 заявок;
2. открывает форму новой заявки;
3. проверяет данные на сервере;
4. сохраняет новую заявку в MS SQL Server;
5. после POST выполняет redirect, поэтому обновление страницы не дублирует запись;
6. возвращает 400, 404 и 405 для некорректных запросов.

POST-запрос ограничен 16 КБ; запрос большего размера получает ответ 413.

В запросах к базе применены параметры с явными типами и длинами. HTML-данные
кодируются, а ответы содержат базовые защитные заголовки CSP, `nosniff`,
`DENY` для iframe и запрет кэширования.

Маршруты:

- `/` — список заявок;
- `/new` — форма создания;
- `/create` — обработка POST-запроса.

## Структура базы данных

- `Departments` — справочник подразделений;
- `RequestStatuses` — справочник статусов;
- `ServiceRequests` — заявки сотрудников.

Таблица `ServiceRequests` связана внешними ключами с обоими справочниками.

## Структура репозитория

```text
HelpDeskWeb/
├── README.md
├── TEST_REPORT.md
├── docs/
│   └── ANALYSIS.md
├── sql/
│   ├── 01_create_database.sql
│   ├── 02_grant_iis_access.sql
│   ├── 03_smoke_test.sql
│   └── 04_permissions_test.sql
├── src/
│   ├── HelpDeskWeb.dpr
│   ├── HelpDeskWeb.dproj
│   ├── DbUnit.pas
│   ├── WebModuleUnit.pas
│   ├── WebModuleUnit.dfm
│   └── Win32/
│       └── Release/
│           └── HelpDeskWeb.dll
└── tests/
    ├── validate_project.py
    └── Test-HelpDeskWeb.ps1
```

## Требуемое программное обеспечение

- Windows 10 или Windows 11;
- Delphi 10.2 Tokyo с поддержкой WebBroker по условию задачи; исходники не
  используют новые языковые возможности и могут быть открыты в Delphi 12;
- Microsoft SQL Server Express или другая редакция SQL Server;
- SQL Server Management Studio;
- Microsoft OLE DB Driver 19 for SQL Server (`MSOLEDBSQL19`) и Microsoft
  Visual C++ Redistributable x86;
- Internet Information Services (IIS) с компонентом **ISAPI Extensions**.

## 1. Создание базы данных

1. Откройте SQL Server Management Studio.
2. Подключитесь к экземпляру SQL Server, например `localhost\SQLEXPRESS`.
3. Откройте `sql/01_create_database.sql`.
4. Нажмите **Execute**.
5. Откройте `sql/03_smoke_test.sql` и выполните его.
6. Успешный результат: `SMOKE TEST PASSED`.

> Внимание: повторный запуск `01_create_database.sql` удаляет и заново создаёт
> три учебные таблицы вместе с данными. Не запускайте его поверх рабочей базы.

По умолчанию приложение подключается к `.\SQLEXPRESS` с Windows-аутентификацией.
Для другого сервера задайте переменную окружения
`HELPDESKWEB_CONNECTION_STRING` для процесса IIS и перезапустите пул. Пример
для локального учебного стенда:

```text
Provider=MSOLEDBSQL19;Data Source=.\SQLEXPRESS;Initial Catalog=HelpDeskWebDB;Integrated Security=SSPI;DataTypeCompatibility=80;Use Encryption for Data=Optional;TrustServerCertificate=True;
```

`TrustServerCertificate=True` и `Use Encryption for Data=Optional` допустимы для локального учебного стенда.
В рабочей среде установите доверенный сертификат SQL Server и используйте
`TrustServerCertificate=False`.

## 2. Компиляция в Delphi 10.2

1. Откройте `src/HelpDeskWeb.dproj`.
2. В списке платформ выберите **Windows 32-bit**.
3. Выберите конфигурацию **Release**.
4. Выполните **Project → Build HelpDeskWeb**.
5. DLL должна появиться в папке:

```text
src\Win32\Release\HelpDeskWeb.dll
```

Если файл `.dproj` не открывается, откройте `HelpDeskWeb.dpr`; Delphi создаст служебный проектный файл заново.

### Ручная сборка в Delphi 12 Community Edition

Откройте тот же `src/HelpDeskWeb.dproj`. Delphi 12 может предложить обновить
служебный формат проекта; исходные `.pas` и `.dfm` при этом менять не требуется.
Файл проекта содержит полные секции `ProjectExtensions`, `BorlandProject`,
конфигурацию `Base` и явное описание Win32, необходимые проектному менеджеру IDE.
Выберите **Windows 32-bit** и **Release**, затем выполните
**Project → Build HelpDeskWeb**. В данном комплекте автоматическая компиляция не
заявлена: итог сборки должен быть подтверждён вручную в IDE.

## 3. Настройка IIS

### Включение компонентов Windows

В разделе **Включение или отключение компонентов Windows** включите:

- Internet Information Services;
- Web Management Tools → IIS Management Console;
- World Wide Web Services → Application Development Features → ISAPI Extensions;
- World Wide Web Services → Common HTTP Features → Static Content.

### Создание приложения

1. Создайте папку `C:\inetpub\wwwroot\HelpDeskWeb`.
2. Скопируйте туда `HelpDeskWeb.dll`.
3. В IIS Manager создайте пул приложений **HelpDeskWebPool**.
4. Для пула задайте:
   - `.NET CLR Version` — **No Managed Code**;
   - `Enable 32-Bit Applications` — **True**;
   - Identity — **ApplicationPoolIdentity**.
5. В `Default Web Site` создайте приложение с псевдонимом `HelpDeskWeb`.
6. Укажите физический путь `C:\inetpub\wwwroot\HelpDeskWeb` и пул `HelpDeskWebPool`.
7. В приложении откройте **Authentication** → **Anonymous Authentication** → **Edit** и выберите **Application pool identity**.
8. На уровне сервера откройте **ISAPI and CGI Restrictions**.
9. Добавьте `C:\inetpub\wwwroot\HelpDeskWeb\HelpDeskWeb.dll` и разрешите выполнение.
10. В **Handler Mappings** приложения убедитесь, что ISAPI DLL разрешена для выполнения, а в **Edit Feature Permissions** включено **Execute**.

DLL собирается как Win32, поэтому пул должен разрешать 32-разрядные приложения,
а на сервере должна быть доступна 32-разрядная часть OLE DB-драйвера. Установщик
x64 драйвера устанавливает обе разрядности, но для него также требуется
Visual C++ Redistributable x86.

## 4. Выдача IIS доступа к базе

После создания пула `HelpDeskWebPool` выполните в SQL Server Management Studio файл:

```text
sql/02_grant_iis_access.sql
```

Скрипт создаёт пользователя `IIS APPPOOL\HelpDeskWebPool` и выдаёт минимальные
права: `SELECT` на три таблицы и `INSERT` на `ServiceRequests`. Права `UPDATE`,
`DELETE` и `db_owner` не выдаются.

Схема с виртуальной учётной записью пула рассчитана на IIS и SQL Server на одном
компьютере. Для удалённого SQL Server используйте отдельную доменную сервисную
учётную запись и выдайте те же объектные права.

Затем выполните:

```text
sql/04_permissions_test.sql
```

Успешный результат: `PERMISSIONS TEST PASSED`.

## 5. Проверка в браузере

Откройте:

```text
http://localhost/HelpDeskWeb/HelpDeskWeb.dll/
```

Проверьте:

1. отображается список двух тестовых заявок;
2. ссылка **Создать заявку** открывает форму;
3. пустая форма не отправляется браузером;
4. заполненная форма создаёт новую запись;
5. новая запись появляется в общем списке;
6. неизвестный адрес, например `/unknown`, возвращает ошибку 404;
7. GET-запрос к `/create` возвращает ошибку 405 и заголовок `Allow: POST`;
8. отправка несуществующего `department_id` возвращает 400, а не 500;
9. POST размером более 16 КБ возвращает 413;
10. ответы содержат защитные HTTP-заголовки.

После ручной проверки выполните интеграционный тест из корня проекта:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Test-HelpDeskWeb.ps1
```

Тест отправляет реальные GET/POST-запросы, проверяет ответы 200/400/404/405/413,
защитные заголовки и создаёт одну заявку с уникальной темой `HTTP TEST ...`.

Статическую проверку комплекта можно запустить без Delphi, IIS и SQL Server:

```powershell
python .\tests\validate_project.py
```

## Типовые ошибки с которыми я столкнулся при выполнении и проверки задания

### `Provider cannot be found`

Не установлен Microsoft OLE DB Driver 19 for SQL Server или его 32-разрядная часть. Установите драйвер и перезапустите IIS.

### `Login failed for user IIS APPPOOL\HelpDeskWebPool`

Не выполнен `sql/02_grant_iis_access.sql` либо имя пула отличается от `HelpDeskWebPool`.

### Ошибка 404.2 или 404.3

Не включён компонент ISAPI Extensions или не настроено сопоставление обработчика DLL.

### Ошибка 500

Проверьте `HELPDESKWEB_CONNECTION_STRING`, наличие базы `HelpDeskWebDB`, права
пула приложений и журнал IIS. Текст внутреннего исключения не показывается
пользователю, но передаётся в журнал WEB-сервера.