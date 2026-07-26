[CmdletBinding()]
param(
  [string]$BaseUrl = 'http://localhost/HelpDeskWeb/HelpDeskWeb.dll'
)

$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if ($Condition) {
    $script:Passed++
    Write-Host "PASS | $Message"
  }
  else {
    $script:Failed++
    Write-Host "FAIL | $Message"
  }
}

function Invoke-ErrorRequest {
  param([scriptblock]$Request)

  try {
    $response = & $Request
    return [PSCustomObject]@{
      Status = [int]$response.StatusCode
      Headers = $response.Headers
    }
  }
  catch {
    if ($null -eq $_.Exception.Response) {
      throw
    }

    return [PSCustomObject]@{
      Status = [int]$_.Exception.Response.StatusCode
      Headers = $_.Exception.Response.Headers
    }
  }
}

$BaseUrl = $BaseUrl.TrimEnd('/')

$list = Invoke-WebRequest -Uri "$BaseUrl/" -Method Get -UseBasicParsing
Assert-True ($list.StatusCode -eq 200) 'GET / возвращает 200'
Assert-True ($list.Content -match '<h2>Заявки</h2>') 'GET / показывает список заявок'
Assert-True ($list.Headers['X-Content-Type-Options'] -eq 'nosniff') 'Ответ содержит X-Content-Type-Options'
Assert-True ($list.Headers['X-Frame-Options'] -eq 'DENY') 'Ответ содержит X-Frame-Options'
Assert-True ($list.Headers['Content-Security-Policy'] -match "default-src 'none'") 'Ответ содержит Content-Security-Policy'

$form = Invoke-WebRequest -Uri "$BaseUrl/new" -Method Get -UseBasicParsing
Assert-True ($form.StatusCode -eq 200) 'GET /new возвращает 200'
Assert-True ($form.Content -match '<form method="post"') 'GET /new показывает POST-форму'

$unknown = Invoke-ErrorRequest {
  Invoke-WebRequest -Uri "$BaseUrl/unknown" -Method Get -UseBasicParsing
}
Assert-True ($unknown.Status -eq 404) 'Неизвестный маршрут возвращает 404'

$wrongMethod = Invoke-ErrorRequest {
  Invoke-WebRequest -Uri "$BaseUrl/create" -Method Get -UseBasicParsing
}
Assert-True ($wrongMethod.Status -eq 405) 'GET /create возвращает 405'
Assert-True ($wrongMethod.Headers['Allow'] -eq 'POST') 'Ответ 405 содержит Allow: POST'

$oversized = Invoke-ErrorRequest {
  Invoke-WebRequest -Uri "$BaseUrl/create" -Method Post -UseBasicParsing -Body @{
    employee_name = 'HTTP-тест'
    department_id = '1'
    subject = 'Слишком большой запрос'
    description = ('x' * 17000)
  }
}
Assert-True ($oversized.Status -eq 413) 'POST размером более 16 КБ возвращает 413'

$badDepartment = Invoke-ErrorRequest {
  Invoke-WebRequest -Uri "$BaseUrl/create" -Method Post -UseBasicParsing -Body @{
    employee_name = 'HTTP-тест'
    department_id = '999999'
    subject = 'Некорректное подразделение'
    description = 'Запись не должна быть добавлена.'
  }
}
Assert-True ($badDepartment.Status -eq 400) 'Несуществующее подразделение возвращает 400'

$uniqueSubject = 'HTTP TEST ' + [Guid]::NewGuid().ToString('N')
$created = Invoke-WebRequest -Uri "$BaseUrl/create" -Method Post -UseBasicParsing -Body @{
  employee_name = 'Интеграционный тест'
  department_id = '1'
  subject = $uniqueSubject
  description = 'Тестовая заявка, созданная tests/Test-HelpDeskWeb.ps1.'
}
Assert-True ($created.StatusCode -eq 200) 'POST /create следует за 303 и открывает список'
Assert-True ($created.Content -match [regex]::Escape($uniqueSubject)) 'Созданная заявка присутствует в списке'

$occurrences = [regex]::Matches($created.Content, [regex]::Escape($uniqueSubject)).Count
Assert-True ($occurrences -eq 1) 'POST создал ровно одну заявку'

Write-Host ""
Write-Host "Итого: $($script:Passed) пройдено, $($script:Failed) ошибок."

if ($script:Failed -ne 0) {
  exit 1
}
