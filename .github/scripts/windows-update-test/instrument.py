"""Inject diagnostics only into the disposable CI checkout, never the app release."""
from pathlib import Path

backend = Path('src-tauri/src/lib.rs')
source = backend.read_text()
needle = '            install_update\n'
assert source.count(needle) == 1, 'unexpected command handler layout'
source = source.replace(needle, '            install_update,\n            ci_test_log\n')
source += '''\n#[tauri::command]\nfn ci_test_log(message: String) {\n    use std::io::Write;\n    let path = std::path::PathBuf::from(std::env::var_os("RUNNER_TEMP").unwrap_or_else(|| std::env::temp_dir().into_os_string())).join("auto-clicker-update-test").join("events.log");\n    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(path) {\n        let _ = writeln!(f, "{}", message);\n    }\n}\n'''
backend.write_text(source)
frontend = Path('src/main.ts')
with frontend.open('a') as f:
    f.write('''\n// Disposable CI-only instrumentation; production releases do not contain this code.\nsetTimeout(async () => {\n  const log = (message: string) => invoke('ci_test_log', { message });\n  try {\n    await log('test started');\n    const found = await invoke<{version: string} | null>('check_update');\n    if (!found || found.version !== '0.1.1') throw new Error('Expected test update 0.1.1');\n    await log('update found 0.1.1');\n    await log('install requested');\n    await invoke('install_update');\n  } catch (error) { await log(`error: ${String(error)}`); }\n}, 8000);\n''')
print('Injected temporary CI-only updater instrumentation')
