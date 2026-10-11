# Publica o Unitec Mesas na GitHub Release (sem Codemagic).
#
# Fluxo completo:
#   1) valida versão (pubspec.yaml = lib/app_info.dart)
#   2) gera APK release assinado com a chave local
#   3) commit + push do código (se houver alteração)
#   4) cria tag vX.Y.Z e publica Release com APK + .sha256 + notas
#
# Uso (na raiz do projeto, com gh autenticado):
#   powershell -ExecutionPolicy Bypass -File tool\publicar-release.ps1
#   powershell -ExecutionPolicy Bypass -File tool\publicar-release.ps1 -Mensagem "feat(app): ..."
#
# Antes de cada versão nova: suba X.Y.Z+N em pubspec.yaml e em lib/app_info.dart.
# A chave fica fora do Git: android/key.properties + ci/unitecmesas-release.p12

param(
    [string]$Mensagem = ''
)

$ErrorActionPreference = 'Stop'
# git/gh escrevem diagnóstico em stderr; no PowerShell isso não deve abortar o script.
$PSNativeCommandUseErrorActionPreference = $false
$Repo = 'unitecnologia/unitec-mesas'
$Raiz = Split-Path -Parent $PSScriptRoot
Set-Location $Raiz

function Read-KeyProp([string]$name) {
    $line = Select-String -Path 'android\key.properties' -Pattern "^${name}=" | Select-Object -First 1
    if (-not $line) { throw "android/key.properties sem '$name'." }
    return ($line.Line -replace "^${name}=", '').Trim()
}

if (-not (Test-Path 'android\key.properties')) {
    throw "Falta android/key.properties. Copie de android/key.properties.example."
}
$StorePass = Read-KeyProp 'storePassword'
$KeyAlias = Read-KeyProp 'keyAlias'
$StoreType = Read-KeyProp 'storeType'
$StoreFileRel = Read-KeyProp 'storeFile'
$StoreFile = [IO.Path]::GetFullPath((Join-Path (Join-Path $Raiz 'android\app') $StoreFileRel))
if (-not (Test-Path $StoreFile)) {
    throw "Keystore não encontrada: $StoreFile (storeFile=$StoreFileRel)."
}

$pub = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$nome, $code = $pub -split '\+'
$info = Get-Content lib\app_info.dart -Raw
$infoNome = [regex]::Match($info, "kAppVersion = '([^']+)'").Groups[1].Value
$infoCode = [regex]::Match($info, 'kAppBuild = (\d+)').Groups[1].Value
if ($infoNome -ne $nome -or $infoCode -ne $code) {
    throw "lib/app_info.dart ($infoNome+$infoCode) diferente do pubspec ($pub)."
}
$Tag = "v$nome"
Write-Host "Unitec Mesas $Tag (versionCode $code)"

# 1) APK release assinado (só ARM — celulares reais)
Write-Host '>> Gerando APK release...'
flutter build apk --release --target-platform android-arm,android-arm64 --build-name=$nome --build-number=$code
if ($LASTEXITCODE -ne 0) { throw 'Falha no build do APK.' }
$Src = "build\app\outputs\apk\release\Unitec-Mesas-$nome.apk"
if (-not (Test-Path $Src)) { throw "APK não encontrado em $Src" }

# 2) Conferir assinatura = chave local (nunca debug)
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { "$env:LOCALAPPDATA\Android\sdk" }
$apksigner = Get-ChildItem "$sdk\build-tools\*\lib\apksigner.jar" | Sort-Object { [version]$_.Directory.Parent.Name } | Select-Object -Last 1
$jbr = 'C:\Program Files\Android\Android Studio\jbr\bin'
if (-not $apksigner) { throw "apksigner não encontrado em $sdk\build-tools" }
$typeOpt = @()
if ($StoreType) { $typeOpt = @('-storetype', $StoreType) }
$esperado = (& "$jbr\keytool.exe" -list -v -keystore $StoreFile -storepass $StorePass -alias $KeyAlias @typeOpt |
    Select-String 'SHA256:\s*(\S+)').Matches[0].Groups[1].Value.Replace(':', '').ToLower()
$obtido = (& "$jbr\java.exe" -jar $apksigner.FullName verify --print-certs $Src |
    Select-String 'certificate SHA-256 digest:\s*(\S+)').Matches[0].Groups[1].Value.ToLower()
if (-not $esperado -or $esperado -ne $obtido) {
    throw "Assinatura do APK ($obtido) diferente da chave de release ($esperado)."
}
Write-Host "Assinatura OK ($obtido)"

# 3) Arquivos da Release
$Saida = 'build\github-release'
New-Item -ItemType Directory -Force $Saida | Out-Null
$Asset = "unitec-mesas-$nome.apk"
Copy-Item $Src "$Saida\$Asset" -Force
$sha = (Get-FileHash "$Saida\$Asset" -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText("$Raiz\$Saida\$Asset.sha256", "$sha  $Asset`n")
# Notas em ASCII para evitar corrupcao de acentos no PowerShell/Windows.
$notas = @"
Unitec Mesas $Tag

- Versao: $nome (versionCode $code)
- APK: ``$Asset``
- SHA-256 do APK: ``$sha``
- Certificado de assinatura (SHA-256): ``$obtido``

O app consulta esta Release (releases/latest) e so baixa/instala apos o usuario tocar em OK.
"@
[IO.File]::WriteAllText("$Raiz\$Saida\notes.md", $notas, (New-Object Text.UTF8Encoding $false))

# 4) Commit + push (se houver mudanças no código)
if (-not (Test-Path '.git')) { throw 'Pasta ainda não é um repositório Git.' }
git rev-parse --abbrev-ref --symbolic-full-name '@{u}' *> $null
if ($LASTEXITCODE -ne 0) { throw 'Branch local sem remote. Configure origin e faça o primeiro push.' }

$status = git status --porcelain
if ($status) {
    if (-not $Mensagem) {
        $Mensagem = "chore(app): publica $Tag+$code"
    }
    Write-Host '>> Commit e push do código...'
    git add -A
    # Segurança: nunca incluir chave/senha mesmo se .gitignore falhar.
    git diff --cached --name-only | Where-Object {
        $_ -match '(^|/)key\.properties$|\.p12$|\.keystore$|\.jks$'
    } | ForEach-Object { git reset -- $_ -- }
    if (git diff --cached --name-only | Where-Object { $_ -match 'key\.properties|\.p12$|\.keystore$|\.jks$' }) {
        throw 'Abortado: tentativa de versionar chave/senha de assinatura.'
    }
    git commit -m "$Mensagem"
    if ($LASTEXITCODE -ne 0) { throw 'Falha no commit.' }
    git push
    if ($LASTEXITCODE -ne 0) { throw 'Falha no push.' }
} else {
    Write-Host '>> Código já commitado; enviando branch...'
    git push
    if ($LASTEXITCODE -ne 0) { throw 'Falha no push.' }
}

# 5) Tag + Release
$temTag = $false
git rev-parse "refs/tags/$Tag" *> $null
if ($LASTEXITCODE -eq 0) { $temTag = $true }
if (-not $temTag) {
    Write-Host ">> Criando tag $Tag..."
    git tag -a $Tag -m "Unitec Mesas $Tag"
    if ($LASTEXITCODE -ne 0) { throw "Falha ao criar a tag $Tag." }
    git push origin $Tag
    if ($LASTEXITCODE -ne 0) { throw "Falha ao enviar a tag $Tag." }
} else {
    Write-Host ">> Tag $Tag já existe localmente."
    git push origin $Tag *> $null
}

Write-Host '>> Publicando GitHub Release...'
$releaseExiste = $false
gh release view $Tag --repo $Repo *> $null
if ($LASTEXITCODE -eq 0) { $releaseExiste = $true }
if ($releaseExiste) {
    gh release upload $Tag "$Saida\$Asset" "$Saida\$Asset.sha256" --repo $Repo --clobber
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao atualizar os arquivos da Release.' }
    gh release edit $Tag --repo $Repo --notes-file "$Saida\notes.md" --title "Unitec Mesas $Tag"
} else {
    gh release create $Tag "$Saida\$Asset" "$Saida\$Asset.sha256" `
        --repo $Repo `
        --title "Unitec Mesas $Tag" `
        --notes-file "$Saida\notes.md"
}
if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar a GitHub Release.' }

Write-Host ""
Write-Host "Publicado: https://github.com/$Repo/releases/tag/$Tag"
Write-Host "Canal do app: https://api.github.com/repos/$Repo/releases/latest"
