#include "system_tray.h"
#include "resource.h"

SystemTray::SystemTray(HWND hwnd, HINSTANCE hinstance)
    : window_(hwnd), hinstance_(hinstance), menu_(nullptr) {
  ZeroMemory(&nid_, sizeof(NOTIFYICONDATA));
}

SystemTray::~SystemTray() {
  RemoveTrayIcon();
  if (menu_) {
    DestroyMenu(menu_);
  }
}

bool SystemTray::Initialize() {
  nid_.cbSize = sizeof(NOTIFYICONDATA);
  nid_.hWnd = window_;
  nid_.uID = 1;
  nid_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid_.uCallbackMessage = WM_TRAYICON;

  // Load the application icon
  nid_.hIcon = LoadIcon(hinstance_, MAKEINTRESOURCE(IDI_APP_ICON));
  if (!nid_.hIcon) {
    // Fallback to default application icon
    nid_.hIcon = LoadIcon(NULL, IDI_APPLICATION);
  }

  // Set default tooltip
  wcscpy_s(nid_.szTip, L"Time Trak");

  // Add the icon to the system tray
  if (!Shell_NotifyIcon(NIM_ADD, &nid_)) {
    return false;
  }

  CreateTrayMenu();
  return true;
}

void SystemTray::UpdateTooltip(const std::wstring &text) {
  wcscpy_s(nid_.szTip, text.c_str());
  Shell_NotifyIcon(NIM_MODIFY, &nid_);
}

void SystemTray::UpdateMenuItems(bool check_in_enabled, bool check_out_enabled,
                                 bool break_in_enabled,
                                 bool break_out_enabled) {
  if (!menu_)
    return;

  EnableMenuItem(menu_, ID_TRAY_CHECK_IN,
                 check_in_enabled ? MF_ENABLED : MF_GRAYED);
  EnableMenuItem(menu_, ID_TRAY_CHECK_OUT,
                 check_out_enabled ? MF_ENABLED : MF_GRAYED);
  EnableMenuItem(menu_, ID_TRAY_BREAK_IN,
                 break_in_enabled ? MF_ENABLED : MF_GRAYED);
  EnableMenuItem(menu_, ID_TRAY_BREAK_OUT,
                 break_out_enabled ? MF_ENABLED : MF_GRAYED);
}

void SystemTray::HandleTrayMessage(WPARAM wparam, LPARAM lparam) {
  if (lparam == WM_RBUTTONUP) {
    // Right-click: show context menu
    ShowContextMenu();
  } else if (lparam == WM_LBUTTONUP) {
    // Left-click: restore/show window
    if (menu_callback_) {
      menu_callback_(ID_TRAY_SHOW_WINDOW);
    }
  }
}

void SystemTray::SetMenuCallback(MenuCallback callback) {
  menu_callback_ = callback;
}

void SystemTray::ShowContextMenu() {
  if (!menu_)
    return;

  POINT cursor_pos;
  GetCursorPos(&cursor_pos);

  // Required for proper menu behavior
  SetForegroundWindow(window_);

  UINT clicked = TrackPopupMenu(menu_, TPM_RETURNCMD | TPM_NONOTIFY,
                                cursor_pos.x, cursor_pos.y, 0, window_, NULL);

  if (clicked != 0 && menu_callback_) {
    menu_callback_(clicked);
  }
}

void SystemTray::CreateTrayMenu() {
  menu_ = CreatePopupMenu();

  AppendMenu(menu_, MF_STRING, ID_TRAY_CHECK_IN, L"Check In");
  AppendMenu(menu_, MF_STRING, ID_TRAY_CHECK_OUT, L"Check Out");
  AppendMenu(menu_, MF_SEPARATOR, 0, NULL);
  AppendMenu(menu_, MF_STRING, ID_TRAY_BREAK_IN, L"Break In");
  AppendMenu(menu_, MF_STRING, ID_TRAY_BREAK_OUT, L"Break Out");
  AppendMenu(menu_, MF_SEPARATOR, 0, NULL);
  AppendMenu(menu_, MF_STRING, ID_TRAY_QUIT, L"Quit");
}

void SystemTray::RemoveTrayIcon() { Shell_NotifyIcon(NIM_DELETE, &nid_); }
