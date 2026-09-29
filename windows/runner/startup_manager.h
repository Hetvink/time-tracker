#ifndef RUNNER_STARTUP_MANAGER_H_
#define RUNNER_STARTUP_MANAGER_H_

#include <string>
#include <windows.h>

class StartupManager {
public:
  // Enable auto-start on Windows login
  static bool EnableAutoStart();

  // Disable auto-start
  static bool DisableAutoStart();

  // Check if auto-start is enabled
  static bool IsAutoStartEnabled();

private:
  static std::wstring GetExecutablePath();
  static const wchar_t *GetRegistryKey();
  static const wchar_t *GetAppName();
};

#endif // RUNNER_STARTUP_MANAGER_H_
