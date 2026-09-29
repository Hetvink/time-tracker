#ifndef ACTIVE_WINDOW_TRACKER_H_
#define ACTIVE_WINDOW_TRACKER_H_

#include <X11/Xlib.h>
#include <functional>
#include <string>

class ActiveWindowTracker {
 public:
  using ActivityCallback = std::function<void(
      const std::string& app_name,
      const std::string& window_title,
      const std::string& window_class)>;

  explicit ActiveWindowTracker(ActivityCallback callback);
  ~ActiveWindowTracker();

  void StartTracking();
  void StopTracking();
  bool IsTracking() const { return is_tracking_; }

  struct CurrentActivity {
    std::string app_name;
    std::string window_title;
    std::string window_class;
  };

  CurrentActivity GetCurrentActivity();

 private:
  static gboolean TimeoutCallback(gpointer user_data);
  void CheckActiveWindow();
  std::string GetWindowTitle(Window window);
  std::string GetWindowClass(Window window);
  std::string GetProcessName(Window window);

  Display* display_;
  ActivityCallback callback_;
  bool is_tracking_ = false;
  guint timer_id_ = 0;
  std::string last_app_name_;
  std::string last_window_title_;
  std::string last_window_class_;
};

#endif  // ACTIVE_WINDOW_TRACKER_H_
