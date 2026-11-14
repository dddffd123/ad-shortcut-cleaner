# ==========================================================
#  은밀한 청소기 v1.5 — 은밀한 광고를 청소해 주는 은밀한 청소기
#  (옛 이름: 쇼핑 광고 바로가기 청소기)
#  재부팅할 때마다 즐겨찾기/바로가기에 생기는 쿠팡·지마켓·마켓컬리 등
#  광고 링크를 찾아서 지우고, 그걸 만드는 원인 프로그램까지 정리합니다.
#
#  - 알려진 광고 주소: 바로 지움 (자동 청소 포함)
#  - 의심 항목(쇼핑몰 이름인데 공식 주소가 아니거나 광고 추적 주소):
#      직접 실행할 때 골라서 지움. 자동 청소는 절대 지우지 않고 알림만.
#  - 광고 목록 = 기본 목록 + patterns.txt + 온라인 목록(설정한 경우)
#  - 지우기 전에 항상 백업을 만듭니다.
# ==========================================================
param(
    [switch]$ScanOnly,      # 검사만 하고 아무것도 지우지 않음
    [switch]$NoPause,       # 끝날 때 엔터 대기 안 함
    [switch]$Auto,          # 자동 청소 모드 (창 없이, 묻지 않고 실행 — 예약 작업이 사용)
    [switch]$EnableAuto,    # 자동 청소 켜기
    [switch]$DisableAuto    # 자동 청소 끄기
)

$Version = '1.5'

# ===== 온라인 광고 목록 주소 (비워 두면 사용 안 함) =====
# patterns.txt 와 같은 형식의 텍스트 파일 주소. 여기 목록을 고치면 공유한 모든 사람에게 반영됩니다.
$RemoteListUrl = 'https://raw.githubusercontent.com/dddffd123/ad-shortcut-cleaner/main/online-list.txt'

Remove-TypeData System.Array -ErrorAction SilentlyContinue   # PS 5.1 JSON 배열 버그 방지
if (-not $Auto) {
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
    try { $Host.UI.RawUI.WindowTitle = "은밀한 청소기 v$Version" } catch {}
}

$AppDir   = Join-Path $env:LOCALAPPDATA 'AdShortcutCleaner'   # 자동 청소/설정 저장 위치
$TaskName = 'AdShortcutCleaner'
$StartMenuLink = Join-Path ([Environment]::GetFolderPath('Programs')) '은밀한 청소기.lnk'
$OldStartMenuLink = Join-Path ([Environment]::GetFolderPath('Programs')) '쇼핑 광고 바로가기 청소기.lnk'   # v1.3 이하 이름

# ===== 기본 목록 =====
# [ad] 알려진 광고 주소 (정규식) — 발견 즉시 지움
$BuiltinAd = @(
    'ad\.altools\.co\.kr'      # 이스트소프트 알툴즈(알매니저) 광고
    'socialfriendsinc\.com'    # 스케두(Socialfriends) 광고
    'coupa\.ng'                # 쿠팡 파트너스 광고 단축 링크
    'sharedid=KRbookmarks'     # 즐겨찾기 삽입용 제휴 광고 (에어비앤비 등)
)
# [shop] 쇼핑몰 이름 (정규식) — 이 이름인데 공식 주소가 아니면 "의심 항목"
$BuiltinShop = @(
    '쿠팡','coupang','지마켓','g마켓','gmarket','옥션','auction','11번가','11st','컬리','kurly',
    'ssg','신세계','이마트','emart','롯데온','lotteon','롯데몰','롯데홈','테무','temu','알리익스','aliexpress',
    '오늘의집','지그재그','zigzag','무신사','musinsa','29cm','w컨셉','wconcept','더블유컨셉','하프클럽','halfclub',
    '교보','kyobo','예스24','yes24','예스이십사','알라딘','aladin','인터파크','interpark','위메프','티몬',
    '아고다','agoda','trip\.com','트립닷컴','호텔스닷컴','hotels\.com','부킹닷컴','booking\.com','야놀자','여기어때',
    '아이허브','iherb','네이버\s*\+?\s*스토어','스마트스토어','숨고','에어비앤비','airbnb',
    'gs\s*shop','cj온스타일','현대몰','hmall'
)
# ※ "쇼핑/특가" 같은 일반 단어는 넣지 않음 — 직접 저장한 작은 쇼핑몰까지 의심하게 됨
# [official] 공식 도메인 — 이 주소(또는 하위 주소)면 정상
$BuiltinOfficial = @(
    'coupang.com','coupangplay.com','coupangeats.com','gmarket.co.kr','auction.co.kr','11st.co.kr','kurly.com','ssg.com','emart.com',
    'lotteon.com','lotte.com','lotteimall.com','temu.com','aliexpress.com','aliexpress.us','ohou.se','zigzag.kr',
    'musinsa.com','29cm.co.kr','wconcept.co.kr','halfclub.com','kyobobook.co.kr','yes24.com','aladin.co.kr',
    'interpark.com','wemakeprice.com','tmon.co.kr','agoda.com','trip.com','hotels.com','booking.com',
    'yanolja.com','goodchoice.kr','yeogi.com','iherb.com','naver.com','soomgo.com','airbnb.co.kr','airbnb.com',
    'gsshop.com','cjonstyle.com','hmall.com'
)
# 공식 주소라도 이런 게 붙어 있으면 광고 추적 링크로 보고 의심
$TrackerRegex = '(?i)(link\.coupang\.com/a/|[?&](sharedid|subid|sub_id|aff_?id|affiliate|partner_?id|clickid)=|utm_medium=(affiliate|partner|cps)|redirect_?url|linkprice|/click\?|/redirect\?)'
# 패턴 안전검사: 이 정상 주소에 걸리는 [ad] 패턴은 너무 넓으므로 무시
$SafeUrls = @('https://www.google.com/','https://www.naver.com/','https://m.naver.com/','https://www.coupang.com/',
              'https://www.gmarket.co.kr/','https://www.11st.co.kr/','https://www.youtube.com/','https://www.daum.net/','https://github.com/')

$Browsers = @(
    @{ Name = 'Microsoft Edge'; Dir = "$env:LOCALAPPDATA\Microsoft\Edge\User Data";               Proc = 'msedge' }
    @{ Name = 'Chrome';         Dir = "$env:LOCALAPPDATA\Google\Chrome\User Data";               Proc = 'chrome' }
    @{ Name = '네이버 웨일';    Dir = "$env:LOCALAPPDATA\Naver\Naver Whale\User Data";           Proc = 'whale'  }
    @{ Name = 'Brave';          Dir = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; Proc = 'brave'  }
)

# ---------------------------------------------------------- 도우미
function Say([string]$t, [string]$c = 'Gray') { if (-not $Auto) { Write-Host $t -ForegroundColor $c } }
function Ask([string]$q) {
    while ($true) {
        $a = Read-Host "$q (Y/N)"
        if ($a -match '^\s*[yYㅛ]') { return $true }
        if ($a -match '^\s*[nNㅜ]') { return $false }
    }
}
function Pause-End { if (-not $NoPause -and -not $Auto) { Read-Host "`n엔터를 누르면 닫힙니다" | Out-Null } }
function Get-Kids($node) { @($node.children | Where-Object { $null -ne $_ }) }
function Write-Utf8([string]$path, [string]$text) {
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $true))
}

# ---------------------------------------------------------- 광고 목록 불러오기
$script:AdList = New-Object System.Collections.Generic.List[string]
$script:ShopList = New-Object System.Collections.Generic.List[string]
$script:OfficialList = New-Object System.Collections.Generic.List[string]
$script:PatternNotes = New-Object System.Collections.Generic.List[string]

function Add-Patterns([string]$text, [string]$from) {
    $sec = 'ad'
    foreach ($line in ($text -split "`r?`n")) {
        $l = ($line -replace '\s+#.*$', '').Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        if ($l -match '^\[(ad|official|shop)\]$') { $sec = $Matches[1]; continue }
        if ($sec -eq 'ad') {
            try { $rx = New-Object regex $l, 'IgnoreCase' } catch { $script:PatternNotes.Add("[$from] 잘못된 패턴이라 무시: $l"); continue }
            if (@($SafeUrls | Where-Object { $rx.IsMatch($_) }).Count) { $script:PatternNotes.Add("[$from] 정상 사이트까지 걸리는 패턴이라 무시: $l"); continue }
            $script:AdList.Add($l)
        } elseif ($sec -eq 'shop') {
            try { $null = New-Object regex $l; $script:ShopList.Add($l) } catch { $script:PatternNotes.Add("[$from] 잘못된 패턴이라 무시: $l") }
        } else {
            if ($l -match '^[a-z0-9.-]+\.[a-z]{2,}$') { $script:OfficialList.Add($l.ToLower()) }
            else { $script:PatternNotes.Add("[$from] 잘못된 도메인이라 무시: $l") }
        }
    }
}

function Load-Patterns {
    Add-Patterns ("[ad]`n" + ($BuiltinAd -join "`n") + "`n[shop]`n" + ($BuiltinShop -join "`n") + "`n[official]`n" + ($BuiltinOfficial -join "`n")) '기본'

    $local = Join-Path $PSScriptRoot 'patterns.txt'
    if (Test-Path -LiteralPath $local) { Add-Patterns ([IO.File]::ReadAllText($local, [Text.Encoding]::UTF8)) 'patterns.txt' }

    $cache = Join-Path $AppDir 'patterns-online.txt'
    $script:RemoteStatus = '사용 안 함'
    if ($RemoteListUrl) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $r = Invoke-WebRequest -Uri $RemoteListUrl -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
            $txt = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()).TrimStart([char]0xFEFF)
            if ($txt -match '(?m)^\s*\[(ad|shop|official)\]') { Write-Utf8 $cache $txt; $script:RemoteStatus = '최신 목록 받음' }
            else { $script:RemoteStatus = '받은 내용이 목록 형식이 아님 — 저장된 목록 사용' }
        } catch { $script:RemoteStatus = '받기 실패(인터넷 확인) — 저장된 목록 사용' }
        if (Test-Path -LiteralPath $cache) { Add-Patterns ([IO.File]::ReadAllText($cache, [Text.Encoding]::UTF8)) '온라인' }
    }

    $script:AdRegex   = '(?i)(' + ((@($script:AdList) | Select-Object -Unique) -join '|') + ')'
    $script:ShopRegex = '(?i)(' + ((@($script:ShopList) | Select-Object -Unique) -join '|') + ')'
    $script:Official  = @($script:OfficialList | Select-Object -Unique)
}

# 의심 항목 중 "지우지 않음"으로 고른 주소
$KeepFile = Join-Path $AppDir 'keep.txt'
$script:Keep = New-Object 'System.Collections.Generic.HashSet[string]'
if (Test-Path -LiteralPath $KeepFile) {
    [IO.File]::ReadAllLines($KeepFile, [Text.Encoding]::UTF8) | Where-Object { $_.Trim() } | ForEach-Object { [void]$script:Keep.Add($_.Trim()) }
}
# 이번에 지우기로 고른 의심 주소
$script:ExtraUrls = New-Object 'System.Collections.Generic.HashSet[string]'

$Shell = New-Object -ComObject WScript.Shell

# 바로가기(.url/.lnk) 안에 들어있는 모든 글자를 꺼냄
function Get-ShortcutText($f) {
    $parts = @()
    try {
        if ($f.Extension -eq '.url') {
            $parts += [IO.File]::ReadAllText($f.FullName)
        } else {
            try { $s = $Shell.CreateShortcut($f.FullName); $parts += "$($s.TargetPath) $($s.Arguments)" } catch {}
            $b = [IO.File]::ReadAllBytes($f.FullName)
            $parts += [Text.Encoding]::Unicode.GetString($b)
            if ($b.Length -gt 1) { $parts += [Text.Encoding]::Unicode.GetString($b, 1, $b.Length - 1) }
            $parts += [Text.Encoding]::ASCII.GetString($b)
        }
    } catch {}
    $parts -join "`n"
}

function Test-KnownAd([string]$url) { $url -and ($url -match $script:AdRegex -or $script:ExtraUrls.Contains($url)) }

# 쇼핑몰 이름인데 공식 주소가 아니거나 광고 추적 주소면 의심
function Test-Suspect([string]$name, [string]$url) {
    if (-not $url -or $url -match $script:AdRegex -or $script:Keep.Contains($url)) { return $false }
    if ("$name" -notmatch $script:ShopRegex) { return $false }   # 이름 기준 (주소 기준은 오탐이 많음)
    $u = $null
    if (-not [uri]::TryCreate($url, 'Absolute', [ref]$u) -or $u.Scheme -notin 'http', 'https') { return $false }
    $h = $u.Host.ToLower()
    $isOfficial = @($script:Official | Where-Object { $h -eq $_ -or $h.EndsWith('.' + $_) }).Count -gt 0
    if (-not $isOfficial) { return $true }
    return ($url -match $TrackerRegex)
}

# 크롬 계열 즐겨찾기 트리에서 광고 항목 제거 (광고 때문에 비게 된 폴더도 제거)
function Clean-Node($node, [string]$path, $list) {
    if (-not ($node.PSObject.Properties.Name -contains 'children')) { return }
    $keep = New-Object System.Collections.ArrayList
    foreach ($c in (Get-Kids $node)) {
        if ($c.type -eq 'url' -and (Test-KnownAd "$($c.url)")) {
            [void]$list.Add("$path/$($c.name)"); continue
        }
        if ($c.type -eq 'folder') {
            $had = (Get-Kids $c).Count
            $n0 = $list.Count
            Clean-Node $c "$path/$($c.name)" $list
            if ($had -gt 0 -and (Get-Kids $c).Count -eq 0 -and $list.Count -gt $n0) {
                [void]$list.Add("[폴더] $path/$($c.name)"); continue
            }
        }
        [void]$keep.Add($c)
    }
    $node.children = [object[]]$keep.ToArray()
}

function Clean-BookmarkJson($json, $list) {
    foreach ($p in $json.roots.PSObject.Properties) {
        if ($p.Value -and $p.Value.PSObject.Properties.Name -contains 'children') {
            Clean-Node $p.Value $p.Value.name $list
        }
    }
}

function Get-BookmarkUrls($node, [string]$path, $out) {
    foreach ($c in (Get-Kids $node)) {
        if ($c.type -eq 'url') { [void]$out.Add([pscustomobject]@{ Name = "$($c.name)"; Url = "$($c.url)"; Where = $path }) }
        elseif ($c.type -eq 'folder') { Get-BookmarkUrls $c "$path/$($c.name)" $out }
    }
}

function Read-Bookmarks([string]$path) { [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json }

# ---------------------------------------------------------- 검사
function Find-AdItems {
    $roots = @(
        [Environment]::GetFolderPath('Favorites')
        [Environment]::GetFolderPath('Desktop')
        [Environment]::GetFolderPath('CommonDesktopDirectory')
        [Environment]::GetFolderPath('StartMenu')
        [Environment]::GetFolderPath('CommonStartMenu')
        "$env:USERPROFILE\Links"
        "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    $files = @(); $sus = @()
    foreach ($r in $roots) {
        Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.url', '.lnk' } |
            Where-Object { $_.FullName -notmatch '\\광고바로가기_백업_\d' -and -not $_.FullName.StartsWith($AppDir, [StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object {
                $txt = Get-ShortcutText $_
                $m = [regex]::Match($txt, "https?://[^\s\x00""']*$($script:AdRegex)[^\s\x00""']*")
                if (-not $m.Success) { $m = [regex]::Match($txt, $script:AdRegex) }
                if ($m.Success) { $files += [pscustomobject]@{ File = $_; Url = $m.Value }; return }
                $um = [regex]::Match($txt, 'https?://[^\s\x00"''<>]+')
                if ($um.Success -and (Test-Suspect $_.BaseName $um.Value)) {
                    $sus += [pscustomobject]@{ Kind = 'file'; Name = $_.BaseName; Url = $um.Value; Where = $_.FullName; File = $_ }
                }
            }
    }
    $files = @($files | Sort-Object { $_.File.FullName } -Unique)
    $sus = @($sus | Sort-Object { $_.File.FullName } -Unique)

    $bms = @()
    foreach ($b in $Browsers) {
        if (-not (Test-Path -LiteralPath $b.Dir)) { continue }
        Get-ChildItem -LiteralPath $b.Dir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $f = Join-Path $_.FullName 'Bookmarks'
            if (-not (Test-Path -LiteralPath $f)) { return }
            try { $json = Read-Bookmarks $f } catch { Say "  (읽기 실패: $f)" DarkYellow; return }
            $all = New-Object System.Collections.ArrayList
            foreach ($p in $json.roots.PSObject.Properties) {
                if ($p.Value -and $p.Value.PSObject.Properties.Name -contains 'children') { Get-BookmarkUrls $p.Value $p.Value.name $all }
            }
            $seen = @{}
            foreach ($u in $all) {
                if (-not $seen.ContainsKey($u.Url) -and (Test-Suspect $u.Name $u.Url)) {
                    $seen[$u.Url] = 1
                    $sus += [pscustomobject]@{ Kind = 'bookmark'; Name = $u.Name; Url = $u.Url; Where = "$($b.Name) ($($_.Name)) / $($u.Where)"
                                               Browser = $b.Name; Proc = $b.Proc; Profile = $_.Name; Path = $f }
                }
            }
            $list = New-Object System.Collections.ArrayList
            Clean-BookmarkJson $json $list
            if ($list.Count -gt 0) {
                $bms += [pscustomobject]@{ Browser = $b.Name; Proc = $b.Proc; Profile = $_.Name; Path = $f; Removed = $list }
            }
        }
    }
    [pscustomobject]@{ Files = $files; Bookmarks = $bms; Suspects = $sus }
}

# ---------------------------------------------------------- 정리
# $fileItems: 지울 바로가기 파일들, $bmTargets: 정리할 즐겨찾기 파일들(Browser/Proc/Profile/Path)
# 반환: 기록(문자열 목록). $script:Done / $script:Fail 에 개수 누적
function Remove-AdItems($fileItems, $bmTargets, [string]$backup) {
    $log = New-Object System.Collections.ArrayList
    New-Item -ItemType Directory -Path $backup -Force | Out-Null

    $i = 0
    foreach ($f in $fileItems) {
        $i++
        try {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $backup ("{0:D3}_{1}" -f $i, $f.Name)) -Force
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            [void]$log.Add(("[삭제] {0:D3}_{1}  <=  {2}" -f $i, $f.Name, $f.FullName)); $script:Done++
        } catch {
            [void]$log.Add("[실패] $($f.FullName) : $($_.Exception.Message)"); $script:Fail++
            Say "  삭제 실패(관리자 권한 필요할 수 있음): $($f.FullName)" DarkYellow
        }
    }

    $bmTargets = @($bmTargets | Sort-Object Path -Unique)
    foreach ($proc in ($bmTargets | Select-Object -ExpandProperty Proc -Unique)) {
        $name = ($bmTargets | Where-Object Proc -eq $proc | Select-Object -First 1).Browser
        $running = @(Get-Process -Name $proc -ErrorAction SilentlyContinue)
        if ($running.Count) {
            if ($Auto) {
                # 창이 하나도 없으면(백그라운드 실행 중) 닫고 정리, 창이 열려 있으면 다음 차례로 미룸
                if (@($running | Where-Object { $_.MainWindowHandle -ne 0 }).Count -eq 0) {
                    $running | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3
                }
            } else {
                Say ''
                Say "  $name 이(가) 실행 중입니다. 브라우저를 닫아야 즐겨찾기를 정리할 수 있어요." Yellow
                if (Ask "  $name 을(를) 지금 닫을까요?") {
                    $running | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3
                }
            }
        }
        foreach ($x in ($bmTargets | Where-Object Proc -eq $proc)) {
            if (Get-Process -Name $proc -ErrorAction SilentlyContinue) {
                Say "  $name 이(가) 아직 열려 있어 건너뜁니다." DarkYellow
                [void]$log.Add("[보류] $name 이(가) 열려 있어 즐겨찾기 정리를 미룸"); $script:Fail++; continue
            }
            $bk = Join-Path $backup ("{0}_{1}_Bookmarks" -f ($x.Browser -replace '\s', ''), $x.Profile)
            try {
                $json = Read-Bookmarks $x.Path             # 닫힌 뒤의 최신 내용으로 다시 읽음
                $list = New-Object System.Collections.ArrayList
                Clean-BookmarkJson $json $list
                if ($list.Count -eq 0) { continue }
                Copy-Item -LiteralPath $x.Path -Destination $bk -Force
                $json.PSObject.Properties.Remove('checksum')
                $txt = $json | ConvertTo-Json -Depth 100 -Compress
                $null = $txt | ConvertFrom-Json            # 제대로 된 파일인지 확인
                [IO.File]::WriteAllText($x.Path, $txt, (New-Object Text.UTF8Encoding $false))
                $bak = "$($x.Path).bak"
                if (Test-Path -LiteralPath $bak) { Copy-Item -LiteralPath $bak -Destination "$bk.bak" -Force; Remove-Item -LiteralPath $bak -Force }
                [void]$log.Add("[정리] $($x.Browser) ($($x.Profile)) 즐겨찾기 $($list.Count)개 항목  (원본: $bk)")
                $list | ForEach-Object { [void]$log.Add("        - $_") }
                $script:Done += @($list | Where-Object { $_ -notlike '[폴더]*' }).Count
            } catch {
                if (Test-Path -LiteralPath $bk) { Copy-Item -LiteralPath $bk -Destination $x.Path -Force }
                [void]$log.Add("[실패] $($x.Path) : $($_.Exception.Message) (원래대로 되돌림)"); $script:Fail++
                Say "  $($x.Browser) 즐겨찾기 정리 실패 — 원래대로 되돌렸습니다." DarkYellow
            }
        }
    }
    , $log
}

function Write-Record([string]$backup, $log) {
    $head = @(
        "은밀한 청소기 v$Version - 정리 기록 ($(Get-Date))"
        '되돌리려면: 브라우저를 닫고, 이 폴더의 *_Bookmarks 파일을 원래 위치에 "Bookmarks"라는 이름으로 덮어쓰세요.'
        '바로가기 파일은 앞의 번호(001_)를 떼고 원래 경로에 복사하면 됩니다.'
        ''
    )
    [IO.File]::WriteAllLines((Join-Path $backup '정리기록.txt'), [string[]]($head + $log), (New-Object Text.UTF8Encoding $true))
}

# Windows 알림 (자동 청소에서 의심 항목 발견 시)
function Show-Toast([string]$title, [string]$msg) {
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $e = { param($s) [Security.SecurityElement]::Escape($s) }
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$(& $e $title)</text><text>$(& $e $msg)</text></binding></visual></toast>")
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch {}
}

# ---------------------------------------------------------- 자동 청소 켜기/끄기
function Get-AutoTask { Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }

function Enable-AutoClean {
    New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
    $script = Join-Path $AppDir 'cleaner.ps1'
    if ($PSCommandPath -ne $script) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $script -Force
        $pt = Join-Path $PSScriptRoot 'patterns.txt'
        if (Test-Path -LiteralPath $pt) { Copy-Item -LiteralPath $pt -Destination (Join-Path $AppDir 'patterns.txt') -Force }
    }

    $ps  = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Auto"
    # 검은 창이 번쩍이지 않도록 conhost --headless 로 실행 (Windows 10 1903 이상).
    # VBScript(wscript)는 최신 Windows에서 꺼져 있을 수 있어 쓰지 않음.
    $conhost = "$env:SystemRoot\System32\conhost.exe"
    $build = 0; try { $build = [int](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).BuildNumber } catch {}
    if ((Test-Path -LiteralPath $conhost) -and $build -ge 18362) {
        $action = New-ScheduledTaskAction -Execute $conhost -Argument "--headless `"$ps`" $psArgs"
    } else {
        $action = New-ScheduledTaskAction -Execute $ps -Argument $psArgs
    }
    Remove-Item -LiteralPath (Join-Path $AppDir 'run-hidden.vbs') -Force -ErrorAction SilentlyContinue
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $atLogon = New-ScheduledTaskTrigger -AtLogOn -User $user
    $atLogon.Delay = 'PT1M'
    $hourly = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 1)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Description '은밀한 청소기 - 로그인 1분 뒤와 1시간마다 광고 즐겨찾기를 자동으로 정리합니다.' `
        -Action $action -Trigger @($atLogon, $hourly) -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null

    # 시작 메뉴에 바로가기 (알림을 받았을 때 여기서 실행)
    Remove-Item -LiteralPath $OldStartMenuLink -Force -ErrorAction SilentlyContinue
    try {
        $s = $Shell.CreateShortcut($StartMenuLink)
        $s.TargetPath = $ps
        $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
        $s.WorkingDirectory = $AppDir
        $s.Description = '은밀한 청소기'
        $s.Save()
    } catch {}
}

function Disable-AutoClean {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $AppDir 'run-hidden.vbs'), $StartMenuLink, $OldStartMenuLink -Force -ErrorAction SilentlyContinue
    if ($PSCommandPath -ne (Join-Path $AppDir 'cleaner.ps1')) {
        Remove-Item -LiteralPath (Join-Path $AppDir 'cleaner.ps1') -Force -ErrorAction SilentlyContinue
    }
}

# 테스트용: ". .\cleaner.ps1" 로 불러오면 목록만 읽고 함수만 정의한 뒤 멈춤
if ($MyInvocation.InvocationName -eq '.') { Load-Patterns; return }

# ========================================================== 명령: 자동 청소 켜기/끄기
if ($EnableAuto -or $DisableAuto) {
    try {
        if ($EnableAuto) { Enable-AutoClean; Say '자동 청소를 켰습니다.' Green }
        else { Disable-AutoClean; Say '자동 청소를 껐습니다.' Green }
    } catch { Say "실패: $($_.Exception.Message)" Red }
    Pause-End; return
}

Load-Patterns

# ========================================================== 자동 모드 (창 없음, 질문 없음)
if ($Auto) {
    New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
    $logFile = Join-Path $AppDir 'log.txt'
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
    try {
        $found = Find-AdItems
        if (@($found.Files).Count -or @($found.Bookmarks).Count) {
            $script:Done = 0; $script:Fail = 0
            $backup = Join-Path $AppDir ('backup\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
            $log = Remove-AdItems @($found.Files | ForEach-Object { $_.File }) $found.Bookmarks $backup
            Write-Record $backup $log
            Add-Content -LiteralPath $logFile -Encoding UTF8 -Value ("{0}  자동 정리: {1}개 삭제, 보류/실패 {2}개  ({3})" -f $stamp, $script:Done, $script:Fail, $backup)
        }
        # 의심 항목은 지우지 않고, 새로 생겼을 때만 알림
        $sus = @($found.Suspects)
        $notified = Join-Path $AppDir 'notified.txt'
        $key = (@($sus | ForEach-Object { $_.Url } | Sort-Object -Unique) -join "`n")
        $old = if (Test-Path -LiteralPath $notified) { [IO.File]::ReadAllText($notified, [Text.Encoding]::UTF8) } else { '' }
        if ($sus.Count -and $key -ne $old) {
            Show-Toast '광고로 의심되는 즐겨찾기가 있어요' ("{0}개 발견. 시작 메뉴에서 '은밀한 청소기'를 실행해 확인하세요." -f $sus.Count)
            Add-Content -LiteralPath $logFile -Encoding UTF8 -Value ("{0}  의심 항목 {1}개 발견 (지우지 않음, 알림 보냄)" -f $stamp, $sus.Count)
        }
        Write-Utf8 $notified $key
        # 30일 지난 백업은 삭제
        Get-ChildItem -LiteralPath (Join-Path $AppDir 'backup') -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-30) } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Add-Content -LiteralPath $logFile -Encoding UTF8 -Value ("{0}  오류: {1}" -f $stamp, $_.Exception.Message)
    }
    return
}

# ========================================================== 1. 검사
Clear-Host
Say '=================================================' Cyan
Say "        은밀한 청소기 v$Version" Cyan
Say '=================================================' Cyan
Say ''
Say '검사 중입니다...'

$found = Find-AdItems
$AdFiles = @($found.Files)
$AdBookmarks = @($found.Bookmarks)
$Suspects = @($found.Suspects)

$UninstallEntries = Get-ItemProperty @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
) -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }

$SchedoTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -ne $TaskName -and
    (($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments) $($_.WorkingDirectory)" }) -join ' ') -match 'schedo'
})
$SchedoApp = $UninstallEntries | Where-Object { $_.DisplayName -match '스케두|schedo' -or $_.Publisher -match 'socialfriends' } | Select-Object -First 1
$AlManager = $UninstallEntries | Where-Object { $_.DisplayName -match '알매니저|ALTools ?Manager' } | Select-Object -First 1

# ========================================================== 2. 결과 보고
Say ''
Say '[ 검사 결과 ]' Yellow
$bmCount = 0; $AdBookmarks | ForEach-Object { $bmCount += @($_.Removed | Where-Object { $_ -notlike '[폴더]*' }).Count }
Say ("  광고 바로가기 파일   : {0}개" -f $AdFiles.Count)
Say ("  브라우저 광고 즐겨찾기: {0}개" -f $bmCount)
Say ("  의심 항목            : {0}개" -f $Suspects.Count)
if ($RemoteListUrl) { Say "  온라인 광고 목록     : $($script:RemoteStatus)" DarkGray }
$script:PatternNotes | ForEach-Object { Say "  ※ $_" DarkYellow }
if (Test-Path "$env:APPDATA\Mozilla\Firefox\Profiles") { Say '  ※ Firefox 즐겨찾기는 검사하지 못합니다. (Edge/Chrome/웨일/Brave만 지원)' DarkYellow }
Say ''

if ($AdFiles.Count) {
    Say '  ▶ 광고 바로가기 파일' White
    $AdFiles | ForEach-Object { Say ("     - {0}" -f $_.File.FullName) DarkGray }
    Say ''
}
foreach ($x in $AdBookmarks) {
    Say ("  ▶ {0} ({1}) 즐겨찾기" -f $x.Browser, $x.Profile) White
    $x.Removed | ForEach-Object { Say "     - $_" DarkGray }
    Say ''
}
if ($Suspects.Count) {
    Say '[ 의심 항목 ] 광고 목록에는 없지만, 쇼핑몰 이름인데 공식 주소가 아니거나 광고 추적 주소입니다.' Yellow
    for ($n = 0; $n -lt $Suspects.Count; $n++) {
        $s = $Suspects[$n]
        $host_ = try { ([uri]$s.Url).Host } catch { $s.Url }
        Say ("  [{0}] {1}  →  {2}" -f ($n + 1), $s.Name, $host_) White
        Say ("       위치: {0}" -f $s.Where) DarkGray
        Say ("       주소: {0}" -f $(if ($s.Url.Length -gt 90) { $s.Url.Substring(0, 90) + '…' } else { $s.Url })) DarkGray
    }
    Say ''
}

$hasCause = $SchedoTasks.Count -or $AlManager
if ($SchedoApp -and -not $SchedoTasks.Count) {
    Say '[ 스케두 ] 설치되어 있지만 광고 예약 작업은 없습니다. (정상)' DarkGray
    Say '   스케두가 업데이트되며 다시 만들면 다음 검사 때 알려 드려요.' DarkGray
    Say ''
}
if ($hasCause) {
    Say '[ 원인으로 보이는 프로그램 ]' Yellow
    if ($SchedoTasks.Count) {
        Say '  ● 스케두 (Socialfriends Inc.)' Red
        Say '     로그인(재부팅)할 때마다 실행되는 예약 작업이 광고 즐겨찾기를 다시 만듭니다.'
        Say '     광고 주소: socialfriendsinc.com'
    }
    if ($AlManager) {
        Say '  ● 알매니저 (이스트소프트, 알집·알캡처 등과 함께 설치됨)' Red
        Say '     광고 주소: ad.altools.co.kr'
    }
    Say ''
}

$autoTask = Get-AutoTask
Say ("[ 자동 청소 ] {0}" -f $(if ($autoTask) { '켜져 있음' } else { '꺼져 있음' })) Yellow
Say ''

if ($ScanOnly) {
    Say '(검사만 했습니다. 아무것도 지우지 않았습니다.)' Cyan
    Pause-End; return
}
if (-not $AdFiles.Count -and -not $AdBookmarks.Count -and -not $Suspects.Count) {
    Say '광고 바로가기가 발견되지 않았습니다.' Green
}

# ========================================================== 3. 정리
$Backup = Join-Path ([Environment]::GetFolderPath('Desktop')) ('광고바로가기_백업_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Log = New-Object System.Collections.ArrayList
$script:Done = 0; $script:Fail = 0

$delFiles = @(); $bmTargets = @()
if (($AdFiles.Count -or $AdBookmarks.Count) -and (Ask '광고 항목을 지울까요? (지우기 전에 바탕화면에 백업합니다)')) {
    $delFiles += @($AdFiles | ForEach-Object { $_.File })
    $bmTargets += $AdBookmarks
} elseif ($AdFiles.Count -or $AdBookmarks.Count) {
    $script:AdRegex = '(?!)'   # 알려진 광고는 지우지 않기로 함 (의심 항목만 처리)
}

if ($Suspects.Count) {
    Say ''
    Say '  의심 항목 중 지울 번호를 입력하세요.' White
    Say '  예) 1,3,5   전부: A   지우지 않음: 그냥 엔터' DarkGray
    $ans = Read-Host '  번호'
    $pick = @()
    if ($ans -match '^\s*[aAㅁ]\s*$') { $pick = 0..($Suspects.Count - 1) }
    else { $pick = @($ans -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $Suspects.Count } | Select-Object -Unique) }

    foreach ($k in $pick) {
        $s = $Suspects[$k]
        if ($s.Kind -eq 'file') { $delFiles += $s.File }
        else { [void]$script:ExtraUrls.Add($s.Url); $bmTargets += $s }
    }
    $rest = @(0..($Suspects.Count - 1) | Where-Object { $_ -notin $pick } | ForEach-Object { $Suspects[$_] })
    if ($rest.Count -and (Ask ("  고르지 않은 {0}개는 정상으로 기억하고 다음부터 묻지 않을까요?" -f $rest.Count))) {
        $rest | ForEach-Object { [void]$script:Keep.Add($_.Url) }
        Write-Utf8 $KeepFile (($script:Keep | Sort-Object) -join "`r`n")
        Say "  기억했습니다. (되돌리려면 $KeepFile 에서 해당 줄을 지우세요)" DarkGray
    }
}

if ($delFiles.Count -or $bmTargets.Count) {
    $r = Remove-AdItems $delFiles $bmTargets $Backup
    $r | ForEach-Object { [void]$Log.Add($_) }
    Say ''
    Say "  정리 완료: $($script:Done)개 삭제, 실패 $($script:Fail)개" Green
}

# ========================================================== 4. 원인 제거
if ($SchedoTasks.Count) {
    Say ''
    Say '[ 스케두 ] 그대로 두면 재부팅 후 광고가 다시 생깁니다.' Yellow
    Say '   1) 광고 예약 작업만 삭제 (스케두 앱은 계속 사용)'
    Say '   2) 스케두 프로그램 완전 삭제'
    Say '   3) 그대로 두기'
    $c = Read-Host '   번호 선택'
    if ($c -eq '1' -or $c -eq '2') {
        foreach ($t in $SchedoTasks) {
            $full = "$($t.TaskPath)$($t.TaskName)"
            # 실행 중인 광고 프로그램 먼저 멈춤
            try { Stop-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue } catch {}
            foreach ($a in $t.Actions) {
                $exe = [IO.Path]::GetFileNameWithoutExtension("$($a.Execute)".Trim('"'))
                if ($exe) { Get-Process -Name $exe -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
            }
            try {
                Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
            } catch {
                # 관리자 권한으로 등록된 작업은 일반 권한으로 못 지움 → 관리자 권한으로 재시도
                Say "   일반 권한으로는 지울 수 없는 작업입니다. (스케두가 관리자 권한으로 등록함)" DarkYellow
                if (Ask '   관리자 권한으로 다시 시도할까요? (권한 확인 창이 뜨면 "예"를 누르세요)') {
                    try {
                        Start-Process schtasks.exe -ArgumentList "/Delete /TN `"$full`" /F" -Verb RunAs -WindowStyle Hidden -Wait -ErrorAction Stop
                    } catch { Say '   권한 확인 창에서 취소되었습니다.' DarkYellow }
                }
            }
            if (Get-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue) {
                Say "   예약 작업 삭제 실패: $($t.TaskName)" DarkYellow
                Say '   직접 지우려면: 시작 메뉴 → "작업 스케줄러" → 작업 스케줄러 라이브러리 → 해당 작업 우클릭 → 삭제' DarkGray
            } else {
                Say "   예약 작업 삭제: $($t.TaskName)" Green; [void]$Log.Add("[원인] 예약 작업 삭제: $full")
            }
        }
    }
    if ($c -eq '2' -and $SchedoApp) {
        Say '   스케두 삭제 프로그램을 엽니다. 창이 뜨면 안내에 따라 진행하세요.'
        Start-Process cmd.exe -ArgumentList "/c `"$($SchedoApp.UninstallString)`"" -Wait
        [void]$Log.Add('[원인] 스케두 삭제 프로그램 실행')
    }
}

if ($AlManager) {
    Say ''
    Say '[ 알매니저 ] 알툴즈 광고(ad.altools.co.kr)를 넣는 관리 프로그램입니다.' Yellow
    Say '   ※ 알집 등 알툴즈 프로그램을 쓰면 다시 설치될 수 있어요. 반디집 같은 대체 프로그램도 고려해 보세요.' DarkGray
    if (Ask '   알매니저를 삭제할까요?') {
        Say '   알매니저 삭제 프로그램을 엽니다. 창이 뜨면 안내에 따라 진행하세요.'
        Start-Process cmd.exe -ArgumentList "/c `"$($AlManager.UninstallString)`"" -Wait
        [void]$Log.Add('[원인] 알매니저 삭제 프로그램 실행')
    }
}

# ========================================================== 5. 자동 청소
Say ''
if (-not $autoTask) {
    Say '[ 자동 청소 ] 광고가 다시 생겨도 알아서 지워 주는 기능입니다.' Yellow
    Say '   로그인 1분 뒤 + 1시간마다 화면에 아무것도 띄우지 않고 검사합니다.' DarkGray
    Say '   알려진 광고만 지우고, 의심 항목은 지우지 않고 알림만 보냅니다.' DarkGray
    Say '   브라우저 창이 열려 있으면 방해하지 않고 다음 차례에 정리합니다.' DarkGray
    if (Ask '   자동 청소를 켤까요?') {
        try { Enable-AutoClean; Say '   자동 청소를 켰습니다. 시작 메뉴에 "은밀한 청소기"도 추가했어요.' Green; [void]$Log.Add('[설정] 자동 청소 켜기') }
        catch { Say "   자동 청소 켜기 실패: $($_.Exception.Message)" Red }
    }
} else {
    try { Enable-AutoClean } catch {}   # 최신 버전으로 갱신
    Say '[ 자동 청소 ] 켜져 있습니다.' Yellow
    if (Ask '   자동 청소를 끌까요?') {
        Disable-AutoClean; Say '   자동 청소를 껐습니다.' Green; [void]$Log.Add('[설정] 자동 청소 끄기')
    }
}

# ========================================================== 6. 마무리
if ($Log.Count -and (Test-Path -LiteralPath $Backup)) {
    Write-Record $Backup $Log
    Say ''
    Say "백업과 기록: $Backup" Cyan
}
Say ''
Say '끝났습니다.' Green
if (Get-AutoTask) { Say "자동 청소 기록은 여기서 볼 수 있어요: $AppDir\log.txt" DarkGray }
Pause-End
