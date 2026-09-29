#include "startup_manager.h"
#include <shlobj.h>

const wchar_t *StartupManager::GetRegistryKey() {
  return L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
}

const wchar_t *StartupManager::GetAppName() { return L"TimeTrak"; }

std::wstring StartupManager::GetExecutablePath() {
  wchar_t path[MAX_PATH];
  GetModuleFileName(NULL, path, MAX_PATH);
  return std::wstring(path);
}

bool StartupManager::EnableAutoStart() {
  HKEY hKey;
  LONG result = RegOpenKeyEx(HKEY_CURRENT_USER, GetRegistryKey(), 0,
                             KEY_SET_VALUE, &hKey);

  if (result != ERROR_SUCCESS) {
    return false;
  }

  std::wstring exe_path = GetExecutablePath();

  result =
      RegSetValueEx(hKey, GetAppName(), 0, REG_SZ, (BYTE *)exe_path.c_str(),
                    (DWORD)((exe_path.length() + 1) * sizeof(wchar_t)));

  RegCloseKey(hKey);
  return result == ERROR_SUCCESS;
}

bool StartupManager::DisableAutoStart() {
  HKEY hKey;
  LONG result = RegOpenKeyEx(HKEY_CURRENT_USER, GetRegistryKey(), 0,
                             KEY_SET_VALUE, &hKey);

  if (result != ERROR_SUCCESS) {
    return false;
  }

  result = RegDeleteValue(hKey, GetAppName());
  RegCloseKey(hKey);

  return result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND;
}

bool StartupManager::IsAutoStartEnabled() {
  HKEY hKey;
  LONG result = RegOpenKeyEx(HKEY_CURRENT_USER, GetRegistryKey(), 0,
                             KEY_QUERY_VALUE, &hKey);

  if (result != ERROR_SUCCESS) {
    return false;
  }

  wchar_t value[MAX_PATH];
  DWORD value_length = sizeof(value);
  DWORD type;

  result = RegQueryValueEx(hKey, GetAppName(), NULL, &type, (LPBYTE)value,
                           &value_length);

  RegCloseKey(hKey);
  return result == ERROR_SUCCESS;
}
