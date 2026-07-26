from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_FILES = [
    '.gitignore',
    'README.md',
    'TEST_REPORT.md',
    'docs/ANALYSIS.md',
    'sql/01_create_database.sql',
    'sql/02_grant_iis_access.sql',
    'sql/03_smoke_test.sql',
    'sql/04_permissions_test.sql',
    'src/HelpDeskWeb.dpr',
    'src/HelpDeskWeb.dproj',
    'src/DbUnit.pas',
    'src/WebModuleUnit.pas',
    'src/WebModuleUnit.dfm',
    'tests/Test-HelpDeskWeb.ps1',
]

checks: list[tuple[str, bool, str]] = []


def add(name: str, condition: bool, details: str = '') -> None:
    checks.append((name, bool(condition), details))


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding='utf-8-sig')


def pascal_lexically_closed(text: str) -> bool:
    """Checks only that Pascal strings and supported comments are closed."""
    i = 0
    state = 'code'
    while i < len(text):
        ch = text[i]
        if state == 'code':
            if ch == "'":
                state = 'string'
            elif text.startswith('//', i):
                state = 'line_comment'
                i += 1
            elif text.startswith('(*', i):
                state = 'paren_comment'
                i += 1
            elif ch == '{':
                state = 'brace_comment'
        elif state == 'string':
            if ch == "'":
                if i + 1 < len(text) and text[i + 1] == "'":
                    i += 1
                else:
                    state = 'code'
        elif state == 'line_comment':
            if ch == '\n':
                state = 'code'
        elif state == 'paren_comment':
            if text.startswith('*)', i):
                state = 'code'
                i += 1
        elif state == 'brace_comment':
            if ch == '}':
                state = 'code'
        i += 1
    return state in {'code', 'line_comment'}


def pascal_code_only(text: str) -> str:
    """Replaces Pascal strings/comments with spaces and preserves newlines."""
    result: list[str] = []
    i = 0
    state = 'code'
    while i < len(text):
        ch = text[i]
        if state == 'code':
            if ch == "'":
                state = 'string'
                result.append(' ')
            elif text.startswith('//', i):
                state = 'line_comment'
                result.extend((' ', ' '))
                i += 1
            elif text.startswith('(*', i):
                state = 'paren_comment'
                result.extend((' ', ' '))
                i += 1
            elif ch == '{':
                state = 'brace_comment'
                result.append(' ')
            else:
                result.append(ch)
        elif state == 'string':
            result.append('\n' if ch == '\n' else ' ')
            if ch == "'":
                if i + 1 < len(text) and text[i + 1] == "'":
                    result.append(' ')
                    i += 1
                else:
                    state = 'code'
        elif state == 'line_comment':
            if ch == '\n':
                state = 'code'
                result.append('\n')
            else:
                result.append(' ')
        elif state == 'paren_comment':
            result.append('\n' if ch == '\n' else ' ')
            if text.startswith('*)', i):
                result.append(' ')
                i += 1
                state = 'code'
        elif state == 'brace_comment':
            result.append('\n' if ch == '\n' else ' ')
            if ch == '}':
                state = 'code'
        i += 1
    return ''.join(result)


def pascal_blocks_balanced(text: str) -> bool:
    """Checks begin/end and the other block forms used by these units."""
    code = pascal_code_only(text)
    tokens = re.findall(r'[A-Za-z_][A-Za-z0-9_]*', code.lower())
    stack: list[str] = []
    unmatched_end = 0
    for index, token in enumerate(tokens):
        if token == 'class' and index + 1 < len(tokens) and tokens[index + 1] == 'of':
            continue
        if token in {'begin', 'case', 'class', 'record', 'object', 'try', 'asm'}:
            stack.append(token)
        elif token in {'except', 'finally'}:
            if not stack or stack[-1] != 'try':
                return False
        elif token == 'end':
            if stack:
                stack.pop()
            else:
                unmatched_end += 1
    expected_terminal_end = 1 if re.match(r'\s*unit\b', code, re.I) else 0
    return not stack and unmatched_end == expected_terminal_end


def normalize_parameters(parameters: str | None) -> str:
    value = parameters or ''
    value = re.sub(r'\s*=\s*[^;)]+', '', value)
    return re.sub(r'\s+', '', value).lower()


def class_method_signatures(text: str) -> dict[str, tuple[str, str, str]]:
    class_match = re.search(
        r'TWebModule1\s*=\s*class\b.*?^\s*end\s*;',
        pascal_code_only(text),
        re.I | re.M | re.S,
    )
    if not class_match:
        return {}
    pattern = re.compile(
        r'\b(procedure|function)\s+([A-Za-z_][A-Za-z0-9_]*)\s*'
        r'(\([^)]*\))?\s*(?::\s*([A-Za-z_.][A-Za-z0-9_.]*))?\s*;',
        re.I | re.S,
    )
    return {
        name.lower(): (kind.lower(), normalize_parameters(parameters), (return_type or '').lower())
        for kind, name, parameters, return_type in pattern.findall(class_match.group(0))
    }


def implemented_method_signatures(text: str) -> dict[str, tuple[str, str, str]]:
    pattern = re.compile(
        r'\b(procedure|function)\s+TWebModule1\.([A-Za-z_][A-Za-z0-9_]*)\s*'
        r'(\([^)]*\))?\s*(?::\s*([A-Za-z_.][A-Za-z0-9_.]*))?\s*;',
        re.I | re.S,
    )
    return {
        name.lower(): (kind.lower(), normalize_parameters(parameters), (return_type or '').lower())
        for kind, name, parameters, return_type in pattern.findall(pascal_code_only(text))
    }


for relative in REQUIRED_FILES:
    add(f'Файл существует: {relative}', (ROOT / relative).is_file())

sql = read('sql/01_create_database.sql')
grants = read('sql/02_grant_iis_access.sql')
smoke = read('sql/03_smoke_test.sql')
permissions_test = read('sql/04_permissions_test.sql')
pas = read('src/WebModuleUnit.pas')
dpr = read('src/HelpDeskWeb.dpr')
dfm = read('src/WebModuleUnit.dfm')
dproj_text = read('src/HelpDeskWeb.dproj')
dbunit = read('src/DbUnit.pas')
analysis = read('docs/ANALYSIS.md')
readme = read('README.md')
gitignore = read('.gitignore')
all_project_text = '\n'.join(
    read(path.relative_to(ROOT).as_posix())
    for path in ROOT.rglob('*')
    if path.is_file() and path.suffix.lower() in {'.pas', '.dpr', '.dfm', '.sql', '.md', '.ps1'}
)

for table in ('Departments', 'RequestStatuses', 'ServiceRequests'):
    add(f'SQL создаёт таблицу {table}', bool(re.search(rf'CREATE\s+TABLE\s+dbo\.{table}\b', sql, re.I)))

add('SQL содержит три первичных ключа', len(re.findall(r'CONSTRAINT\s+PK_', sql, re.I)) == 3)
add('SQL содержит два внешних ключа', len(re.findall(r'CONSTRAINT\s+FK_', sql, re.I)) == 2)
add('Оба внешних ключа ссылаются на справочники',
    'REFERENCES dbo.Departments (DepartmentID)' in sql and
    'REFERENCES dbo.RequestStatuses (StatusID)' in sql)
add('На внешние ключи созданы индексы',
    'IX_ServiceRequests_DepartmentID' in sql and
    'IX_ServiceRequests_StatusID' in sql)
add('SQL защищает обязательные строки CHECK-ограничениями',
    len(re.findall(r'CONSTRAINT\s+CK_ServiceRequests_', sql, re.I)) == 3)
add('SQL использует синтаксис SQL Server',
    'IDENTITY(1,1)' in sql and 'NVARCHAR' in sql and '\nGO\n' in sql)
add('SQL не содержит MySQL-специфичный AUTO_INCREMENT', 'AUTO_INCREMENT' not in sql.upper())
add('Есть тестовые справочные данные',
    'INSERT INTO dbo.Departments' in sql and
    'INSERT INTO dbo.RequestStatuses' in sql)
add('Есть две демонстрационные заявки',
    sql.count('N\'Не печатает принтер\'') == 1 and
    sql.count('N\'Нет доступа к общей папке\'') == 1)
add('IIS получает минимальные объектные права',
    all(token in grants for token in (
        'GRANT SELECT ON dbo.Departments',
        'GRANT SELECT ON dbo.RequestStatuses',
        'GRANT SELECT, INSERT ON dbo.ServiceRequests')) and
    'ADD MEMBER [IIS APPPOOL\\HelpDeskWebPool]' not in grants and
    'db_owner' not in grants.lower())
add('Скрипт удаляет широкие роли ранней версии',
    'ALTER ROLE db_datareader DROP MEMBER' in grants and
    'ALTER ROLE db_datawriter DROP MEMBER' in grants)
add('Скрипт прав IIS рассчитан на HelpDeskWebPool',
    'IIS APPPOOL\\HelpDeskWebPool' in grants)
add('Smoke-тест проверяет таблицы, связи, INSERT и ROLLBACK',
    all(token in smoke for token in ('sys.foreign_keys', 'INSERT INTO dbo.ServiceRequests',
                                     'ROLLBACK TRANSACTION', 'SMOKE TEST PASSED')))
add('Smoke-тест проверяет ограничения, длины и индексы',
    all(token in smoke for token in ('sys.check_constraints', 'COL_LENGTH',
                                     'IX_ServiceRequests_DepartmentID',
                                     'IX_ServiceRequests_StatusID')))
add('Тест прав проверяет разрешённые SELECT и INSERT',
    all(token in permissions_test for token in (
        "HAS_PERMS_BY_NAME(N'dbo.Departments', N'OBJECT', N'SELECT')",
        "HAS_PERMS_BY_NAME(N'dbo.ServiceRequests', N'OBJECT', N'INSERT')",
        'PERMISSIONS TEST PASSED')))
add('Тест прав запрещает UPDATE, DELETE и CONTROL',
    all(token in permissions_test for token in (
        "N'UPDATE'", "N'DELETE'", "N'DATABASE', N'CONTROL'",
        'Пулу IIS выданы избыточные права.')))
add('Тест прав безопасно обрабатывает результат NULL',
    permissions_test.count('ISNULL(@Can') == 7)

for route in ("Path = '/new'", "Path = '/create'", "(Path = '') or (Path = '/')"):
    add(f'Маршрут присутствует: {route}', route in pas)

add('Создание записи выполняется параметризованным запросом',
    all(token in pas for token in (
        ':DepartmentID', ':EmployeeName', ':Subject', ':Description',
        "ParamByName('DepartmentID')", "ParamByName('EmployeeName')",
        "ParamByName('Subject')", "ParamByName('Description')")))
add('Пользовательские данные HTML-кодируются',
    'HtmlEncode' in pas and '&lt;' in pas and '&quot;' in pas and '&#39;' in pas)
add('POST проверяется перед INSERT',
    pas.find('Request.MethodType <> mtPost') < pas.find('INSERT INTO dbo.ServiceRequests'))
add('Некорректное подразделение проверяется до INSERT',
    'DepartmentCount' in pas and
    pas.find('DepartmentCount') < pas.find('INSERT INTO dbo.ServiceRequests') and
    'Выбрано несуществующее подразделение.' in pas)
add('Проверяются обязательные поля и длина',
    'Заполните все обязательные поля.' in pas and
    'Превышена допустимая длина' in pas)
add('Размер POST ограничен до разбора ContentFields',
    pas.find('Request.ContentLength > 16384') <
    pas.find("Request.ContentFields.Values['department_id']") and
    'Размер запроса превышает допустимые 16 КБ.' in pas)
add('Список ограничен последними 200 заявками',
    'SELECT TOP (200)' in pas and 'ORDER BY r.RequestID DESC' in pas)
add('Параметры ADO имеют явные типы и размеры',
    pas.count('DataType := ftWideString') == 3 and
    all(size in pas for size in ('Size := 100;', 'Size := 150;', 'Size := 1000;')))
add('Проверка Path[1] не зависит от режима полного вычисления Boolean',
    "if Path <> '' then" in pas and "(Path <> '') and (Path[1]" not in pas)
add('Ответ формируется в UTF-8 через ContentStream',
    all(token in pas for token in ('TEncoding.UTF8.GetBytes', 'charset=utf-8',
                                   'Response.ContentStream', 'Response.FreeContentStream := True')))
add('Поток ответа освобождается при исключении до передачи Response',
    pas.find('Stream := TBytesStream.Create(Bytes)') <
    pas.find('Response.ContentStream := Stream') <
    pas.find('except\n    Stream.Free'))
add('Ошибка сервера не раскрывает текст исключения пользователю',
    'Response.LogMessage := E.Message' in pas and
    "ShowError(Response, 'Внутренняя ошибка сервера.', 500)" in pas)
add('После POST используется шаблон Post/Redirect/Get',
    'Response.StatusCode := 303' in pas and
    "SendRedirect(Response, AppUrl(Request, '/?created=1'))" in pas)
add('Ответы содержат защитные HTTP-заголовки',
    all(header in pas for header in (
        "'Content-Security-Policy'",
        "SetCustomHeader('X-Content-Type-Options', 'nosniff')",
        "SetCustomHeader('X-Frame-Options', 'DENY')",
        "SetCustomHeader('Referrer-Policy', 'no-referrer')")))
add('Ответ 405 содержит заголовок Allow',
    "Response.SetCustomHeader('Allow', 'POST')" in pas)
add('ISAPI экспортирует обязательные функции',
    all(x in dpr for x in ('GetExtensionVersion', 'HttpExtensionProc', 'TerminateExtension')))
exports_match = re.search(r'\bexports\b(.*?)\bbegin\b', pascal_code_only(dpr), re.I | re.S)
exported_names = set(re.findall(r'\b[A-Za-z_][A-Za-z0-9_]*\b', exports_match.group(1))) if exports_match else set()
add('ISAPI экспортирует ровно три стандартные точки входа',
    exported_names == {'GetExtensionVersion', 'HttpExtensionProc', 'TerminateExtension'})
add('Проект подключает сгенерированный ресурс Delphi',
    '{$R *.res}' in dpr)
add('Подключён WebBroker ISAPIApp',
    'Web.WebBroker' in dpr and 'Web.Win.ISAPIApp' in dpr)
add('COM инициализируется в каждом потоке ISAPI-запроса',
    all(token in pas for token in ('CoInitialize(nil)', 'CoUninitialize',
                                   'ComResult = S_OK', 'ComResult = S_FALSE')))
add('DFM обработчик совпадает с PAS',
    'OnAction = DefaultHandlerAction' in dfm and
    'procedure DefaultHandlerAction' in pas)
add('DFM содержит ожидаемый класс и единственный Default action',
    'object WebModule1: TWebModule1' in dfm and
    dfm.count('Default = True') == 1 and
    dfm.count("PathInfo = '/'") == 1)
add('Структура object/item/end в DFM сбалансирована',
    len(re.findall(r'^\s*(?:object\b|item\b)', dfm, re.I | re.M)) ==
    len(re.findall(r'^\s*end\s*>?\s*$', dfm, re.I | re.M)) and
    dfm.count('<') == dfm.count('>'))
add('Все объявленные обработчики реализованы', all(
    f'TWebModule1.{name}' in pas
    for name in ('HtmlEncode', 'PageHtml', 'AppUrl', 'SendHtml', 'ShowList',
                 'ShowNewForm', 'CreateRequest', 'ShowError', 'DefaultHandlerAction')
))
add('Pascal-строки и комментарии корректно закрыты',
    all(pascal_lexically_closed(text) for text in (pas, dpr, dbunit)))
add('Pascal-блоки begin/end, try и class структурно сбалансированы',
    all(pascal_blocks_balanced(text) for text in (pas, dpr, dbunit)))
add('Объявления и реализации методов TWebModule1 совпадают',
    class_method_signatures(pas) == implemented_method_signatures(pas) and
    len(class_method_signatures(pas)) == 11)
add('Количество try соответствует finally/except',
    len(re.findall(r'\btry\b', pascal_code_only(pas), re.I)) ==
    len(re.findall(r'\bfinally\b', pascal_code_only(pas), re.I)) +
    len(re.findall(r'\bexcept\b', pascal_code_only(pas), re.I)))
add('Локальные ADO-объекты освобождаются во всех трёх обработчиках',
    pas.count('Connection := nil;') == 3 and pas.count('Query := nil;') == 3 and
    pas.count('Connection.Free;') == 3 and pas.count('Query.Free;') == 3)
add('CreateConnection освобождает объект при ошибке Open',
    all(token in dbunit for token in (
        'Result := TADOConnection.Create(nil)', 'except', 'Result.Free;', 'raise;')))
add('Строка подключения использует MS SQL Server OLE DB',
    'Provider=MSOLEDBSQL19' in dbunit and 'Initial Catalog=HelpDeskWebDB' in dbunit)
add('ADO настроен на совместимость типов MSOLEDBSQL',
    'DataTypeCompatibility=80' in dbunit)
add('Встроенная строка использует проверенный локальный режим шифрования ADO',
    all(token in dbunit for token in (
        'Use Encryption for Data=Optional',
        'TrustServerCertificate=True')) and
    'Encrypt=Mandatory' not in dbunit)
add('Строку подключения можно задать через окружение IIS',
    "GetEnvironmentVariable('HELPDESKWEB_CONNECTION_STRING')" in dbunit)
add('Для соединения заданы тайм-ауты',
    'ConnectionTimeout := 10' in dbunit and 'CommandTimeout := 30' in dbunit)
add('В исходниках нет пароля SQL Server', not re.search(r'Password\s*=', dbunit, re.I))
add('Имя базы совпадает в SQL и Delphi',
    'HelpDeskWebDB' in sql and 'HelpDeskWebDB' in dbunit)
add('Поля запросов из Delphi существуют в SQL-схеме', all(
    column in sql for column in (
        'RequestID', 'DepartmentID', 'StatusID', 'EmployeeName',
        'Subject', 'Description', 'CreatedAt', 'DepartmentName', 'StatusName')
))
add('DATETIME2 явно приводится к совместимому с ADO типу datetime',
    'CONVERT(datetime, r.CreatedAt) AS CreatedAt' in pas)
add('Дата заявки выводится в стабильном формате',
    "FormatDateTime('dd.mm.yyyy hh:nn', Query.FieldByName('CreatedAt').AsDateTime)" in pas)
add('Имена unit совпадают с именами PAS-файлов',
    re.search(r'^\s*unit\s+WebModuleUnit\s*;', pas, re.I) is not None and
    re.search(r'^\s*unit\s+DbUnit\s*;', dbunit, re.I) is not None)
add('Между модулями нет циклической зависимости',
    'DbUnit' in pas and 'WebModuleUnit' not in dbunit)
add('USES покрывает все применяемые RTL, ADO и WebBroker-типы',
    all(unit in pas for unit in (
        'Winapi.Windows', 'Winapi.ActiveX', 'System.SysUtils', 'System.Classes',
        'Data.DB', 'Data.Win.ADODB', 'Web.HTTPApp')) and
    all(unit in dpr for unit in ('Web.WebBroker', 'Web.Win.ISAPIApp')))
add('Пользовательский код не передаёт строки или указатели через границу DLL',
    not re.search(
        r'\b(PChar|PAnsiChar|PWideChar|Pointer)\b',
        pascal_code_only(dpr + pas),
        re.I,
    ))
add('В проекте нет собственных external/forward и нестандартных calling convention',
    not re.search(r'\b(external|forward|cdecl|register|safecall)\b', dpr + pas + dbunit, re.I))
add('В проекте нет условных директив, зависящих от платформы',
    not re.search(r'\{\$\s*IF(?:DEF|NDEF)?\b', dpr + pas + dbunit, re.I))

try:
    ET.fromstring(dproj_text)
    xml_ok = True
except ET.ParseError:
    xml_ok = False
add('DPROJ является корректным XML', xml_ok)
add('DPROJ ссылается на исходные модули',
    'WebModuleUnit.pas' in dproj_text and 'DbUnit.pas' in dproj_text)
add('DPR и DPROJ используют реальные относительные пути',
    "WebModuleUnit in 'WebModuleUnit.pas'" in dpr and
    "DbUnit in 'DbUnit.pas'" in dpr and
    not re.search(r'[A-Za-z]:\\', dproj_text))
add('DPROJ настроен как Win32 Library',
    '<Platform Condition="\'$(Platform)\'==\'\'">Win32</Platform>' in dproj_text and
    '<AppType>Library</AppType>' in dproj_text)
add('DPROJ активирует Debug и Release конфигурации',
    all(token in dproj_text for token in (
        "'$(Config)'=='Debug'", '<Cfg_1>true</Cfg_1>',
        "'$(Config)'=='Release'", '<Cfg_2>true</Cfg_2>',
        '<DCC_Optimize>true</DCC_Optimize>')))
add('Release не передаёт false как значение директивы отладочной информации',
    '<DCC_DebugInformation>0</DCC_DebugInformation>' in dproj_text and
    '<DCC_DebugInformation>false</DCC_DebugInformation>' not in dproj_text)
add('DPROJ выводит DLL в Platform/Configuration',
    '<DCC_ExeOutput>.\\$(Platform)\\$(Config)</DCC_ExeOutput>' in dproj_text and
    '<DCC_DcuOutput>.\\$(Platform)\\$(Config)</DCC_DcuOutput>' in dproj_text)
add('DPROJ импортирует стандартные Delphi MSBuild targets',
    '$(BDS)\\Bin\\CodeGear.Delphi.Targets' in dproj_text)
add('DPROJ содержит полные метаданные Delphi IDE',
    all(token in dproj_text for token in (
        '<ProjectExtensions>', '<Borland.Personality>Delphi.Personality.12</Borland.Personality>',
        '<Borland.ProjectType>DynamicLibrary</Borland.ProjectType>',
        '<Source Name="MainSource">HelpDeskWeb.dpr</Source>')))
add('DPROJ содержит базовую конфигурацию проекта',
    '<BuildConfiguration Include="Base">' in dproj_text and
    '<Key>Base</Key>' in dproj_text)
add('DPROJ явно выбирает 32-разрядный компилятор',
    '<DCC_DCCCompiler>DCC32</DCC_DCCCompiler>' in dproj_text and
    '<DCC_Platform>x86</DCC_Platform>' in dproj_text)
add('DPROJ описывает платформы и формат проектного файла для IDE',
    '<ProjectFileVersion>12</ProjectFileVersion>' in dproj_text and
    '<Platform value="Win32">True</Platform>' in dproj_text and
    '<Platform value="Win64">False</Platform>' in dproj_text)

add('Анализ рассматривает четыре рыночные WEB-системы',
    all(name in analysis for name in ('Bitrix24', 'Microsoft Dynamics 365', 'Odoo', '1C:Enterprise')))
add('Анализ содержит варианты использования в компании',
    analysis.count('Варианты использования в компании:') == 4)
add('README содержит полный порядок SQL → Delphi → IIS → проверка',
    all(section in readme for section in (
        '## 1. Создание базы данных', '## 2. Компиляция в Delphi 10.2',
        '## 3. Настройка IIS', '## 4. Выдача IIS доступа к базе',
        '## 5. Проверка в браузере')))
add('Есть воспроизводимый HTTP-интеграционный тест',
    all(token in read('tests/Test-HelpDeskWeb.ps1') for token in (
        'Invoke-WebRequest', '/unknown', '/create', 'department_id',
        'Content-Security-Policy')))
add('В исходниках нет TODO, FIXME, заглушек и временного кода',
    not re.search(r'\b(TODO|FIXME|HACK|stub)\b|заглуш', all_project_text, re.I))
add('Gitignore покрывает артефакты Delphi IDE и сборки',
    all(pattern in gitignore for pattern in (
        'Win32/', 'Win64/', '*.dcu', '*.dll', '*.exe', '*.res', '*.drc', '*.err')))
add('Gitignore исключает локальные файлы базы и резервные копии',
    all(pattern in gitignore for pattern in (
        '*.mdf', '*.ldf', '*.ndf', '*.trn', '*.bak')))
add('Pascal и SQL сохранены как UTF-8 с BOM',
    all(path.read_bytes().startswith(b'\xef\xbb\xbf')
        for path in list((ROOT / 'src').glob('*.pas')) +
                    list((ROOT / 'src').glob('*.dpr')) +
                    list((ROOT / 'sql').glob('*.sql'))))
expected_dll = ROOT / 'src' / 'Win32' / 'Release' / 'HelpDeskWeb.dll'
add('Готовая Win32 Release DLL присутствует',
    expected_dll.is_file() and expected_dll.stat().st_size > 0)
add('В проекте нет лишних DLL или EXE',
    set(ROOT.rglob('*.dll')) == {expected_dll} and not any(ROOT.rglob('*.exe')))
add('В репозитории нет кэша Python', not any(ROOT.rglob('__pycache__')))

failed = [item for item in checks if not item[1]]
for name, ok, details in checks:
    print(('PASS' if ok else 'FAIL') + ' | ' + name + ((' | ' + details) if details else ''))

print(f'\nИтого: {len(checks) - len(failed)}/{len(checks)} проверок пройдено.')
if failed:
    sys.exit(1)
