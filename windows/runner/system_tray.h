#ifndef RUNNER_SYSTEM_TRAY_H_
#define RUNNER_SYSTEM_TRAY_H_

#include <windows.h>
#include <shellapi.h>
#include <string>
#include <functional>

// Message ID for tray icon callbacks
#define WM_TRAYICON (WM_USER + 1)

// Menu item IDs
#define ID_TRAY_CHECK_IN 1001
#define ID_TRAY_CHECK_OUT 1002
#define ID_TRAY_BREAK_IN 1003
#define ID_TRAY_BREAK_OUT 1004
#define ID_TRAY_QUIT 1005
#define ID_TRAY_SHOW_WINDOW 1006

class SystemTray {
 public:
  using MenuCallback = std::function<void(int)>;

  SystemTray(HWND hwnd, HINSTANCE hinstance);
  ~SystemTray();

  // Initialize the system tray icon
  bool Initialize();

  // Update the tray icon tooltip
  void UpdateTooltip(const std::wstring& text);

  // Update menu item states
  void UpdateMenuItems(bool check_in_enabled, bool check_out_enabled,
                      bool break_in_enabled, bool break_out_enabled);

  // Handle tray icon messages
  void HandleTrayMessage(WPARAM wparam, LPARAM lparam);

  // Set callback for menu item clicks
  void SetMenuCallback(MenuCallback callback);

 private:
  void ShowContextMenu();
  void CreateTrayMenu();
  void RemoveTrayIcon();

  HWND window_;
  HINSTANCE hinstance_;
  NOTIFYICONDATA nid_;
  HMENU menu_;
  MenuCallback menu_callback_;
};

#endif  // RUNNER_SYSTEM_TRAY_H_
