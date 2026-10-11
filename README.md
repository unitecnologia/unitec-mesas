# Unitec Mesas

Aplicativo Android do garçom (offline-first) integrado às mesas do PDV do Unitec ERP.

## Atualização automática

O app consulta a [GitHub Release](https://github.com/unitecnologia/unitec-mesas/releases) mais recente
(`releases/latest`), no máximo a cada algumas horas, **sem atrasar a abertura**.

Quando há versão nova, mostra a versão atual, a nova e a pergunta
*"Nova atualização disponível. Deseja atualizar agora?"* com **OK** e **Depois**.

- **Depois:** continua usando o app sem baixar nada.
- **OK:** baixa o APK, valida o SHA-256 e abre o instalador do Android (confirmação do sistema).

Configurações, login, SQLite e pedidos offline **não são apagados** na atualização.

## Publicar uma nova versão (local, sem Codemagic)

1. Suba a versão em `pubspec.yaml` (`X.Y.Z+N`) e em `lib/app_info.dart` (`kAppVersion` / `kAppBuild`).
2. Confirme que existem (fora do Git):
   - `android/key.properties` (copie de `android/key.properties.example`)
   - `ci/unitecmesas-release.p12` (mesma chave em todas as versões)
3. Com `gh` autenticado na conta `unitecnologia`:

```powershell
powershell -ExecutionPolicy Bypass -File tool\publicar-release.ps1
```

O script gera o APK assinado, faz commit/push se necessário, cria a tag `vX.Y.Z` e publica
a Release com APK + `.sha256` + notas.

## Desenvolvimento

```bash
flutter pub get
flutter run
```

Pacote Android: `br.com.unitec.unitec_mesas`.
