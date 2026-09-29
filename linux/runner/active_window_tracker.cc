#include "active_window_tracker.h"

#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <cstring>
#include <glib.h>
#include <iostream>

ActiveWindowTracker::ActiveWindowTracker(ActivityCallback callback)
    : callback_(callback), display_(nullptr) {
  display_ = XOpenDisplay(nullptr);
  if (!display_) {
    std::cerr << "Failed to open X display" << std::endl;
  }
}

ActiveWindowTracker::~ActiveWindowTracker() {
  StopTracking();
  if (display_) {
    XCloseDisplay(display_);
  }
}

void ActiveWindowTracker::StartTracking() {
  if (is_tracking_ || !display_) {
    return;
  }

  is_tracking_ = true;

  // Set timer to check active window every 1 minute (60000 ms)
  timer_id_ = g_timeout_add(60000, TimeoutCallback, this);

  // Check immediately
  CheckActiveWindow();

  std::cout << "[TRACKER] Activity tracking started" << std::endl;
}

void ActiveWindowTracker::StopTracking() {
  if (!is_tracking_) {
    return;
  }

  if (timer_id_ != 0) {
    g_source_remove(timer_id_);
    timer_id_ = 0;
  }

  is_tracking_ = false;
  std::cout << "[TRACKER] Activity tracking stopped" << std::endl;
}

gboolean ActiveWindowTracker::TimeoutCallback(gpointer user_data) {
  auto *tracker = static_cast<ActiveWindowTracker *>(user_data);
  if (tracker) {
    tracker->CheckActiveWindow();
  }
  return G_SOURCE_CONTINUE;
}

void ActiveWindowTracker::CheckActiveWindow() {
  if (!display_) {
    return;
  }

  // Get the currently focused window
  Window focused_window;
  int revert_to;
  XGetInputFocus(display_, &focused_window, &revert_to);

  if (focused_window == None || focused_window == PointerRoot) {
    return;
  }

  // Get window properties
  std::string window_title = GetWindowTitle(focused_window);
  std::string window_class = GetWindowClass(focused_window);
  std::string app_name = GetProcessName(focused_window);

  // Use window class as app name if process name is not available
  if (app_name.empty()) {
    app_name = window_class;
  }

  // Log if window title is empty (helps diagnose issues)
  if (window_title.empty() && app_name != last_app_name_) {
    std::cout << "[TRACKER] No window title for: " << app_name
              << " (window may not have a title)" << std::endl;
  }

  // Check if changed
  bool changed =
      (app_name != last_app_name_ || window_title != last_window_title_ ||
       window_class != last_window_class_);

  if (changed) {
    std::string title_display =
        window_title.empty() ? "(no title)" : window_title;
    std::cout << "[TRACKER] ✓ Activity: " << app_name << " - " << title_display
              << std::endl;

    last_app_name_ = app_name;
    last_window_title_ = window_title;
    last_window_class_ = window_class;

    if (callback_) {
      callback_(app_name, window_title, window_class);
    }
  }
}

std::string ActiveWindowTracker::GetWindowTitle(Window window) {
  if (!display_ || window == None) {
    return "";
  }

  // Try _NET_WM_NAME first (UTF-8)
  Atom net_wm_name = XInternAtom(display_, "_NET_WM_NAME", False);
  Atom utf8_string = XInternAtom(display_, "UTF8_STRING", False);

  Atom actual_type;
  int actual_format;
  unsigned long nitems;
  unsigned long bytes_after;
  unsigned char *prop = nullptr;

  if (XGetWindowProperty(display_, window, net_wm_name, 0, (~0L), False,
                         utf8_string, &actual_type, &actual_format, &nitems,
                         &bytes_after, &prop) == Success &&
      prop) {
    std::string title(reinterpret_cast<char *>(prop));
    XFree(prop);
    return title;
  }

  // Fall back to WM_NAME
  char *window_name = nullptr;
  if (XFetchName(display_, window, &window_name) && window_name) {
    std::string title(window_name);
    XFree(window_name);
    return title;
  }

  return "";
}

std::string ActiveWindowTracker::GetWindowClass(Window window) {
  if (!display_ || window == None) {
    return "";
  }

  XClassHint class_hint;
  if (XGetClassHint(display_, window, &class_hint)) {
    std::string window_class;
    if (class_hint.res_class) {
      window_class = class_hint.res_class;
      XFree(class_hint.res_class);
    }
    if (class_hint.res_name) {
      XFree(class_hint.res_name);
    }
    return window_class;
  }

  return "";
}

std::string ActiveWindowTracker::GetProcessName(Window window) {
  if (!display_ || window == None) {
    return "";
  }

  // Try to get PID from _NET_WM_PID
  Atom net_wm_pid = XInternAtom(display_, "_NET_WM_PID", False);

  Atom actual_type;
  int actual_format;
  unsigned long nitems;
  unsigned long bytes_after;
  unsigned char *prop = nullptr;

  if (XGetWindowProperty(display_, window, net_wm_pid, 0, 1, False, XA_CARDINAL,
                         &actual_type, &actual_format, &nitems, &bytes_after,
                         &prop) == Success &&
      prop) {
    unsigned long pid = *reinterpret_cast<unsigned long *>(prop);
    XFree(prop);

    // Read process name from /proc/[pid]/comm
    std::string comm_path = "/proc/" + std::to_string(pid) + "/comm";
    FILE *fp = fopen(comm_path.c_str(), "r");
    if (fp) {
      char comm[256];
      if (fgets(comm, sizeof(comm), fp)) {
        // Remove trailing newline
        size_t len = strlen(comm);
        if (len > 0 && comm[len - 1] == '\n') {
          comm[len - 1] = '\0';
        }
        fclose(fp);
        return std::string(comm);
      }
      fclose(fp);
    }
  }

  return "";
}

ActiveWindowTracker::CurrentActivity ActiveWindowTracker::GetCurrentActivity() {
  CurrentActivity activity;

  if (!display_) {
    return activity;
  }

  Window focused_window;
  int revert_to;
  XGetInputFocus(display_, &focused_window, &revert_to);

  if (focused_window != None && focused_window != PointerRoot) {
    activity.window_title = GetWindowTitle(focused_window);
    activity.window_class = GetWindowClass(focused_window);
    activity.app_name = GetProcessName(focused_window);

    if (activity.app_name.empty()) {
      activity.app_name = activity.window_class;
    }
  }

  return activity;
}
