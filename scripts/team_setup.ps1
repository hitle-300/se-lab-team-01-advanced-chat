# توزيع المشروع على 3 حسابات GitHub ودمجه (خطة صريحة - Monorepo)
# ============================================================
# التشغيل:
#   1) صاحب الكود (أنشأ المنظمة والمستودع الفارغ) يشغّل أولاً:
#        powershell -ExecutionPolicy Bypass -File scripts\team_setup.ps1 -Step owner -RepoUrl "https://github.com/MyOrg/flutter_client_server.git" -GitName "..." -GitEmail "...@users.noreply.github.com"
#   2) كل عضو على جهازه يشغّل (من مجلد مشروع مسحوب أو فارغ):
#        powershell -ExecutionPolicy Bypass -File scripts\team_setup.ps1 -Step member -RepoUrl "https://github.com/MyOrg/flutter_client_server.git" -BranchName "client-chat" -GitName "..." -GitEmail "...@users.noreply.github.com"
#
# ملاحظات صراحة:
#   - لا تعيد كتابة تاريخ git لتغيير مؤلفي commits الماضية (تزوير).
#   - هذا السكربت يجهّز هوية git محلية (للمستخدم فقط) وفرع عمل لكل عضو،
#     ثم كل عمل مستقبلي يُثبّت باسم صاحب الحساب فعلياً عبر PR.
#   - شرط ظهور المؤلف بشكل صريح في GitHub: GitEmail يجب أن يكون بريد الحساب نفسه.

param(
    [Parameter(Mandatory=$true)][ValidateSet('owner','member')][string]$Step,
    [Parameter(Mandatory=$true)][string]$RepoUrl,
    [Parameter(Mandatory=$true)][string]$GitName,
    [Parameter(Mandatory=$true)][string]$GitEmail,
    [string]$BranchName = ''
)

$ErrorActionPreference = 'Stop'
$RepoDir = Join-Path $env:USERPROFILE 'Desktop\flutter_client_server'

if ($Step -eq 'owner') {
    Write-Host "==> إعداد المستودع المحلي وربطه بالمستودع على GitHub =="
    Set-Location $RepoDir
    git config user.name $GitName
    git config user.email $GitEmail
    git remote remove origin 2>$null
    git remote add origin $RepoUrl
    git push -u origin master
    Write-Host "==> تم رفع master. أضف العضوين الآخرين كـ Collaborators في إعدادات المستودع =="
    exit 0
}

if ($Step -eq 'member') {
    if ([string]::IsNullOrWhiteSpace($BranchName)) {
        throw 'الخطوة member تتطلب -BranchName'
    }
    Write-Host "==> تجهيز جهاز العضو: $GitName على الفرع $BranchName =="
    if (-not (Test-Path $RepoDir)) {
        git clone $RepoUrl $RepoDir
    } else {
        Push-Location $RepoDir
        git fetch --all
        git pull --ff-only 2>$null
        Pop-Location
    }
    Set-Location $RepoDir
    git config user.name $GitName
    git config user.email $GitEmail
    $exists = git branch --list $BranchName
    if ([string]::IsNullOrWhiteSpace($exists)) {
        git checkout -b $BranchName
    } else {
        git checkout $BranchName
    }
    Write-Host "==> جاهز. اعمل على ملفاتك فقط ثم: git add <ملفاتك> / git commit / git push -u origin $BranchName =="
    Write-Host "==> ثم أنشئ Pull Request نحو master من صفحة GitHub =="
    exit 0
}