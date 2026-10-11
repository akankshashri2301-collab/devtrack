# DevTrack API test script
# Usage (server must be running in another terminal):
#   powershell -ExecutionPolicy Bypass -File .\test-api.ps1
# Optional: -BaseUrl http://127.0.0.1:8000

param([string]$BaseUrl = "http://127.0.0.1:8000")

Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(10)

# Random ids so the script can be run many times without "id already exists"
$rid = Get-Random -Minimum 1000 -Maximum 9999
$script:pass = 0
$script:fail = 0

function Send-Request {
    param([string]$Method, [string]$Path, $Body = $null)
    $url = "$BaseUrl$Path"
    if ($Method -eq "POST") {
        $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Compress }
        $content = New-Object System.Net.Http.StringContent($json, [Text.Encoding]::UTF8, "application/json")
        $resp = $client.PostAsync($url, $content).Result
    } else {
        $resp = $client.GetAsync($url).Result
    }
    return [pscustomobject]@{
        Status = [int]$resp.StatusCode
        Body   = $resp.Content.ReadAsStringAsync().Result
    }
}

function Test-Case {
    param([string]$Name, [string]$Method, [string]$Path, $Body, [int]$Expected, [string]$Contains = "")
    try {
        $r = Send-Request -Method $Method -Path $Path -Body $Body
    } catch {
        Write-Host "[FAIL] $Name -> could not reach server. Is runserver running?" -ForegroundColor Red
        $script:fail++
        return
    }
    $ok = ($r.Status -eq $Expected)
    if ($ok -and $Contains -ne "" -and $r.Body -notlike "*$Contains*") { $ok = $false }
    if ($ok) {
        Write-Host "[PASS] $Name (HTTP $($r.Status))" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "[FAIL] $Name (expected $Expected, got $($r.Status))" -ForegroundColor Red
        $script:fail++
    }
    Write-Host "       $Method $Path"
    Write-Host "       $($r.Body)" -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host "`n=== DevTrack API tests ($BaseUrl) ===`n" -ForegroundColor Cyan

# ---------- Reporters ----------
Write-Host "--- Reporters ---" -ForegroundColor Yellow
Test-Case "Create reporter (valid)" POST "/api/reporters/" @{ id = $rid; name = "Panda"; email = "panda@test.com"; team = "backend" } 201
Test-Case "Create reporter (invalid email)" POST "/api/reporters/" @{ id = $rid + 1; name = "Bad"; email = "no-at-sign"; team = "backend" } 400 "Invalid email"
Test-Case "Create reporter (empty name)" POST "/api/reporters/" @{ id = $rid + 2; name = ""; email = "a@b.com"; team = "backend" } 400 "Name cannot be empty"
Test-Case "Get all reporters" GET "/api/reporters/" $null 200
Test-Case "Get reporter by id" GET "/api/reporters/?id=$rid" $null 200 "Panda"
Test-Case "Get reporter by id (not found)" GET "/api/reporters/?id=99999999" $null 404 "Reporter not found"

# ---------- Issues ----------
Write-Host "--- Issues ---" -ForegroundColor Yellow
$issueBase = @{ description = "Test description"; status = "open"; reporter_id = $rid }

Test-Case "Create issue (critical)" POST "/api/issues/" ($issueBase + @{ id = $rid; title = "Login button not working on mobile"; priority = "critical" }) 201 "[URGENT]"
Test-Case "Create issue (low)" POST "/api/issues/" ($issueBase + @{ id = $rid + 1; title = "Typo in footer"; priority = "low" }) 201 "low priority"
Test-Case "Create issue (high, base class)" POST "/api/issues/" ($issueBase + @{ id = $rid + 2; title = "Slow search"; priority = "high" }) 201 "[high]"
Test-Case "Create issue (empty title)" POST "/api/issues/" ($issueBase + @{ id = $rid + 3; title = ""; priority = "low" }) 400 "Title cannot be empty"
$badStatus = $issueBase.Clone()
$badStatus.id = $rid + 4
$badStatus.title = "X"
$badStatus.priority = "low"
$badStatus.status = "done"
Test-Case "Create issue (bad status)" POST "/api/issues/" $badStatus 400 "Status must be"
Test-Case "Create issue (bad priority)" POST "/api/issues/" ($issueBase + @{ id = $rid + 5; title = "X"; priority = "urgent" }) 400 "Priority must be"
Test-Case "Create issue (invalid JSON)" POST "/api/issues/" "{not json" 400 "Invalid JSON"
Test-Case "Get all issues" GET "/api/issues/" $null 200
Test-Case "Get issue by id" GET "/api/issues/?id=$rid" $null 200 "Login button"
Test-Case "Get issue by id (not found)" GET "/api/issues/?id=99999999" $null 404 "Issue not found"
Test-Case "Filter issues by status=open" GET "/api/issues/?status=open" $null 200
Test-Case "Filter issues by status=closed" GET "/api/issues/?status=closed" $null 200

# ---------- Summary ----------
Write-Host "=== Result: $script:pass passed, $script:fail failed ===" -ForegroundColor Cyan
if ($script:fail -gt 0) { exit 1 }
