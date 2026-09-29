#include "my_application.h"

#include <dbus/dbus.h>
#include <flutter_linux/flutter_linux.h>
#include <libappindicator/app-indicator.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "active_window_tracker.h"
#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char **dart_entrypoint_arguments;

  // Native components
  AppIndicator *indicator;
  GtkWidget *menu;
  FlMethodChannel *method_channel;
  FlView *view;
  GtkWindow *window;

  // State tracking
  gchar *current_status;
  gint64 sleep_start_time;
  gint64 wake_time;
  gint sleep_threshold_seconds;
  gboolean is_showing_break_dialog;
  guint midnight_timer_id;

  // Activity tracking
  ActiveWindowTracker *window_tracker;
  gboolean is_tracking_enabled;
  gboolean is_authenticated;

  // D-Bus connection for system events
  DBusConnection *dbus_conn;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Forward declarations
static void setup_system_tray(MyApplication *self);
static void setup_method_channel(MyApplication *self);
static void setup_system_event_monitors(MyApplication *self);
static void show_break_confirmation_dialog(MyApplication *self,
                                           gint64 sleep_start, gint64 wake_time,
                                           gdouble duration);
static void send_system_event(MyApplication *self, const gchar *event_type);
static void send_activity_change(MyApplication *self, const gchar *app_name,
                                 const gchar *window_title,
                                 const gchar *window_class);
static void update_menu_bar_status(MyApplication *self, const gchar *status);
static gboolean check_midnight(gpointer user_data);

// Menu item callbacks
static void on_check_in_clicked(GtkMenuItem *item, gpointer user_data) {
  MyApplication *self = MY_APPLICATION(user_data);
  fl_method_channel_invoke_method(
      self->method_channel, "onUserAction",
      fl_value_new_map_from_strv(
          (const gchar *const[]){"action", "checkIn", nullptr}),
      nullptr, nullptr, nullptr);
}

static void on_check_out_clicked(GtkMenuItem *item, gpointer user_data) {
  MyApplication *self = MY_APPLICATION(user_data);
  fl_method_channel_invoke_method(
      self->method_channel, "onUserAction",
      fl_value_new_map_from_strv(
          (const gchar *const[]){"action", "checkOut", nullptr}),
      nullptr, nullptr, nullptr);
}

static void on_break_in_clicked(GtkMenuItem *item, gpointer user_data) {
  MyApplication *self = MY_APPLICATION(user_data);
  fl_method_channel_invoke_method(
      self->method_channel, "onUserAction",
      fl_value_new_map_from_strv(
          (const gchar *const[]){"action", "breakIn", nullptr}),
      nullptr, nullptr, nullptr);
}

static void on_break_out_clicked(GtkMenuItem *item, gpointer user_data) {
  MyApplication *self = MY_APPLICATION(user_data);
  fl_method_channel_invoke_method(
      self->method_channel, "onUserAction",
      fl_value_new_map_from_strv(
          (const gchar *const[]){"action", "breakOut", nullptr}),
      nullptr, nullptr, nullptr);
}

static void on_open_dashboard_clicked(GtkMenuItem *item, gpointer user_data) {
  MyApplication *self = MY_APPLICATION(user_data);
  if (self->window) {
    gtk_window_present(self->window);
    gtk_window_set_keep_above(self->window, TRUE);
    gtk_window_set_keep_above(self->window, FALSE);
  }
}

static void on_quit_clicked(GtkMenuItem *item, gpointer user_data) {
  MyApplication *self = MY_APPLICATION(user_data);
  g_application_quit(G_APPLICATION(self));
}

// Setup system tray
static void setup_system_tray(MyApplication *self) {
  // Create AppIndicator
  self->indicator =
      app_indicator_new("time-trak-indicator", "clock",
                        APP_INDICATOR_CATEGORY_APPLICATION_STATUS);

  app_indicator_set_status(self->indicator, APP_INDICATOR_STATUS_ACTIVE);
  app_indicator_set_title(self->indicator, "Time Trak");

  // Create menu
  self->menu = gtk_menu_new();

  // Status item
  GtkWidget *status_item = gtk_menu_item_new_with_label("Checked Out");
  gtk_widget_set_sensitive(status_item, FALSE);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu), status_item);
  g_object_set_data(G_OBJECT(self->menu), "status-item", status_item);

  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu),
                        gtk_separator_menu_item_new());

  // Check In
  GtkWidget *check_in_item = gtk_menu_item_new_with_label("Check In");
  g_signal_connect(check_in_item, "activate", G_CALLBACK(on_check_in_clicked),
                   self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu), check_in_item);
  g_object_set_data(G_OBJECT(self->menu), "check-in-item", check_in_item);

  // Check Out
  GtkWidget *check_out_item = gtk_menu_item_new_with_label("Check Out");
  g_signal_connect(check_out_item, "activate", G_CALLBACK(on_check_out_clicked),
                   self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu), check_out_item);
  g_object_set_data(G_OBJECT(self->menu), "check-out-item", check_out_item);

  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu),
                        gtk_separator_menu_item_new());

  // Break In
  GtkWidget *break_in_item = gtk_menu_item_new_with_label("Break In");
  g_signal_connect(break_in_item, "activate", G_CALLBACK(on_break_in_clicked),
                   self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu), break_in_item);
  g_object_set_data(G_OBJECT(self->menu), "break-in-item", break_in_item);

  // Break Out
  GtkWidget *break_out_item = gtk_menu_item_new_with_label("Break Out");
  g_signal_connect(break_out_item, "activate", G_CALLBACK(on_break_out_clicked),
                   self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu), break_out_item);
  g_object_set_data(G_OBJECT(self->menu), "break-out-item", break_out_item);

  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu),
                        gtk_separator_menu_item_new());

  // Open Dashboard
  GtkWidget *open_dashboard_item =
      gtk_menu_item_new_with_label("Open Dashboard");
  g_signal_connect(open_dashboard_item, "activate",
                   G_CALLBACK(on_open_dashboard_clicked), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu), open_dashboard_item);

  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu),
                        gtk_separator_menu_item_new());

  // Quit
  GtkWidget *quit_item = gtk_menu_item_new_with_label("Quit");
  g_signal_connect(quit_item, "activate", G_CALLBACK(on_quit_clicked), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu), quit_item);

  gtk_widget_show_all(self->menu);
  app_indicator_set_menu(self->indicator, GTK_MENU(self->menu));
}

// Method channel handler
static void method_call_handler(FlMethodChannel *channel,
                                FlMethodCall *method_call, gpointer user_data) {
  MyApplication *self = MY_APPLICATION(user_data);
  const gchar *method = fl_method_call_get_name(method_call);
  FlValue *args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "updateMenuBar") == 0) {
    FlValue *status_value = fl_value_lookup_string(args, "status");
    if (status_value &&
        fl_value_get_type(status_value) == FL_VALUE_TYPE_STRING) {
      const gchar *status = fl_value_get_string(status_value);
      update_menu_bar_status(self, status);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (strcmp(method, "updateMenuItems") == 0) {
    FlValue *enabled_items = fl_value_lookup_string(args, "enabledItems");
    if (enabled_items &&
        fl_value_get_type(enabled_items) == FL_VALUE_TYPE_LIST) {
      // Update menu item states
      GtkWidget *check_in =
          GTK_WIDGET(g_object_get_data(G_OBJECT(self->menu), "check-in-item"));
      GtkWidget *check_out =
          GTK_WIDGET(g_object_get_data(G_OBJECT(self->menu), "check-out-item"));
      GtkWidget *break_in =
          GTK_WIDGET(g_object_get_data(G_OBJECT(self->menu), "break-in-item"));
      GtkWidget *break_out =
          GTK_WIDGET(g_object_get_data(G_OBJECT(self->menu), "break-out-item"));

      // Disable all first
      gtk_widget_set_sensitive(check_in, FALSE);
      gtk_widget_set_sensitive(check_out, FALSE);
      gtk_widget_set_sensitive(break_in, FALSE);
      gtk_widget_set_sensitive(break_out, FALSE);

      // Enable based on list
      for (size_t i = 0; i < fl_value_get_length(enabled_items); i++) {
        FlValue *item = fl_value_get_list_value(enabled_items, i);
        if (fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
          const gchar *item_name = fl_value_get_string(item);
          if (strcmp(item_name, "Check In") == 0)
            gtk_widget_set_sensitive(check_in, TRUE);
          else if (strcmp(item_name, "Check Out") == 0)
            gtk_widget_set_sensitive(check_out, TRUE);
          else if (strcmp(item_name, "Break In") == 0)
            gtk_widget_set_sensitive(break_in, TRUE);
          else if (strcmp(item_name, "Break Out") == 0)
            gtk_widget_set_sensitive(break_out, TRUE);
        }
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (strcmp(method, "setSleepThreshold") == 0) {
    FlValue *seconds_value = fl_value_lookup_string(args, "seconds");
    if (seconds_value &&
        fl_value_get_type(seconds_value) == FL_VALUE_TYPE_INT) {
      self->sleep_threshold_seconds = fl_value_get_int(seconds_value);
      g_print("Sleep threshold updated to %d seconds (%d minutes)\n",
              self->sleep_threshold_seconds,
              self->sleep_threshold_seconds / 60);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (strcmp(method, "getAutoStartStatus") == 0) {
    // Check if autostart desktop file exists
    gchar *autostart_dir =
        g_build_filename(g_get_user_config_dir(), "autostart", nullptr);
    gchar *desktop_file =
        g_build_filename(autostart_dir, "time_trak.desktop", nullptr);
    gboolean exists = g_file_test(desktop_file, G_FILE_TEST_EXISTS);
    g_free(autostart_dir);
    g_free(desktop_file);

    g_autoptr(FlValue) result = fl_value_new_bool(exists);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "setAutoStart") == 0) {
    FlValue *enabled_value = fl_value_lookup_string(args, "enabled");
    if (enabled_value &&
        fl_value_get_type(enabled_value) == FL_VALUE_TYPE_BOOL) {
      gboolean enabled = fl_value_get_bool(enabled_value);

      gchar *autostart_dir =
          g_build_filename(g_get_user_config_dir(), "autostart", nullptr);
      g_mkdir_with_parents(autostart_dir, 0755);

      gchar *desktop_file =
          g_build_filename(autostart_dir, "time_trak.desktop", nullptr);

      if (enabled) {
        // Create desktop file
        gchar *exec_path = g_file_read_link("/proc/self/exe", nullptr);
        gchar *content = g_strdup_printf("[Desktop Entry]\n"
                                         "Type=Application\n"
                                         "Name=Time Trak\n"
                                         "Exec=%s\n"
                                         "Icon=clock\n"
                                         "Terminal=false\n"
                                         "X-GNOME-Autostart-enabled=true\n",
                                         exec_path ? exec_path : "time_trak");

        g_file_set_contents(desktop_file, content, -1, nullptr);
        g_free(content);
        g_free(exec_path);
      } else {
        // Remove desktop file
        g_unlink(desktop_file);
      }

      g_free(autostart_dir);
      g_free(desktop_file);

      g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
  } else if (strcmp(method, "startActivityTracking") == 0) {
    if (self->window_tracker) {
      self->window_tracker->StartTracking();
      self->is_tracking_enabled = TRUE;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "stopActivityTracking") == 0) {
    if (self->window_tracker) {
      self->window_tracker->StopTracking();
      self->is_tracking_enabled = FALSE;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "getCurrentActivity") == 0) {
    if (self->window_tracker) {
      auto activity = self->window_tracker->GetCurrentActivity();
      g_autoptr(FlValue) result = fl_value_new_map();
      fl_value_set_string_take(result, "appName",
                               fl_value_new_string(activity.app_name.c_str()));
      fl_value_set_string_take(
          result, "windowTitle",
          fl_value_new_string(activity.window_title.c_str()));
      fl_value_set_string_take(
          result, "bundleId",
          fl_value_new_string(activity.window_class.c_str()));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (strcmp(method, "setAuthenticationStatus") == 0) {
    FlValue *is_authenticated_value =
        fl_value_lookup_string(args, "isAuthenticated");
    if (is_authenticated_value &&
        fl_value_get_type(is_authenticated_value) == FL_VALUE_TYPE_BOOL) {
      self->is_authenticated = fl_value_get_bool(is_authenticated_value);
      g_print("[AUTH] Authentication status updated: %s\n",
              self->is_authenticated ? "true" : "false");
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGS", "Missing isAuthenticated argument", nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void setup_method_channel(MyApplication *self) {
  FlEngine *engine = fl_view_get_engine(self->view);
  FlBinaryMessenger *messenger = fl_engine_get_binary_messenger(engine);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->method_channel = fl_method_channel_new(
      messenger, "com.attendance.tracker/system", FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(self->method_channel,
                                            method_call_handler, self, nullptr);
}

static void update_menu_bar_status(MyApplication *self, const gchar *status) {
  g_free(self->current_status);
  self->current_status = g_strdup(status);

  GtkWidget *status_item =
      GTK_WIDGET(g_object_get_data(G_OBJECT(self->menu), "status-item"));
  if (status_item) {
    gtk_menu_item_set_label(GTK_MENU_ITEM(status_item), status);
  }

  // Update indicator label
  app_indicator_set_label(self->indicator, status, "");
}

static void send_system_event(MyApplication *self, const gchar *event_type) {
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "event", fl_value_new_string(event_type));

  fl_method_channel_invoke_method(self->method_channel, "onSystemEvent", args,
                                  nullptr, nullptr, nullptr);
}

static void send_activity_change(MyApplication *self, const gchar *app_name,
                                 const gchar *window_title,
                                 const gchar *window_class) {
  if (!self->method_channel || !self->is_tracking_enabled)
    return;

  // Get timestamp
  GDateTime *now = g_date_time_new_now_utc();
  gchar *timestamp = g_date_time_format_iso8601(now);

  FlValue *args = fl_value_new_map();
  fl_value_set_string_take(args, "event",
                           fl_value_new_string("activityChange"));
  fl_value_set_string_take(args, "appName", fl_value_new_string(app_name));
  fl_value_set_string_take(args, "windowTitle",
                           fl_value_new_string(window_title));
  fl_value_set_string_take(args, "bundleId", fl_value_new_string(window_class));
  fl_value_set_string_take(args, "timestamp", fl_value_new_string(timestamp));

  fl_method_channel_invoke_method(self->method_channel, "onActivityChange",
                                  args, nullptr, nullptr, nullptr);

  g_free(timestamp);
  g_date_time_unref(now);
}

static void send_break_confirmation(MyApplication *self, gboolean was_on_break,
                                    gint64 sleep_start, gint64 wake_time) {
  g_print("Sending break confirmation: wasOnBreak=%d\n", was_on_break);

  // Convert timestamps to ISO8601
  GDateTime *sleep_dt = g_date_time_new_from_unix_local(sleep_start / 1000000);
  GDateTime *wake_dt = g_date_time_new_from_unix_local(wake_time / 1000000);

  gchar *sleep_str = g_date_time_format_iso8601(sleep_dt);
  gchar *wake_str = g_date_time_format_iso8601(wake_dt);

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "wasOnBreak", fl_value_new_bool(was_on_break));
  fl_value_set_string_take(args, "sleepStart", fl_value_new_string(sleep_str));
  fl_value_set_string_take(args, "wakeTime", fl_value_new_string(wake_str));

  fl_method_channel_invoke_method(self->method_channel, "onBreakConfirmation",
                                  args, nullptr, nullptr, nullptr);

  g_date_time_unref(sleep_dt);
  g_date_time_unref(wake_dt);
  g_free(sleep_str);
  g_free(wake_str);

  self->is_showing_break_dialog = FALSE;
}

static gboolean auto_dismiss_dialog(gpointer user_data) {
  GtkDialog *dialog = GTK_DIALOG(user_data);
  gtk_dialog_response(dialog, GTK_RESPONSE_YES);
  return G_SOURCE_REMOVE;
}

static void show_break_confirmation_dialog(MyApplication *self,
                                           gint64 sleep_start, gint64 wake_time,
                                           gdouble duration) {
  if (self->is_showing_break_dialog) {
    g_print("Break dialog already showing - skipping duplicate\n");
    return;
  }

  self->is_showing_break_dialog = TRUE;

  GtkWidget *dialog = gtk_message_dialog_new(
      self->window, GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION, GTK_BUTTONS_NONE,
      "Were you on break?");

  gint minutes = (gint)(duration / 60);
  gchar *message =
      g_strdup_printf("Your computer was inactive for %d minute%s. Were you on "
                      "a break during this time?",
                      minutes, minutes == 1 ? "" : "s");
  gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog), "%s",
                                           message);
  g_free(message);

  gtk_dialog_add_button(GTK_DIALOG(dialog), "Yes, I was on break",
                        GTK_RESPONSE_YES);
  gtk_dialog_add_button(GTK_DIALOG(dialog), "No, I was working",
                        GTK_RESPONSE_NO);

  // Set up 30-second auto-dismiss timer
  guint timer_id = g_timeout_add_seconds(30, auto_dismiss_dialog, dialog);

  gtk_window_present(GTK_WINDOW(dialog));
  gtk_window_set_keep_above(GTK_WINDOW(dialog), TRUE);

  gint response = gtk_dialog_run(GTK_DIALOG(dialog));

  // Cancel timer if user responded
  g_source_remove(timer_id);

  gboolean was_on_break = (response == GTK_RESPONSE_YES);

  if (response == GTK_RESPONSE_YES || response == GTK_RESPONSE_NO) {
    g_print("User response: %s\n",
            was_on_break ? "Yes (on break)" : "No (working)");
  } else {
    g_print("Break dialog timed out - defaulting to 'was on break'\n");
    was_on_break = TRUE;
  }

  gtk_widget_destroy(dialog);

  send_break_confirmation(self, was_on_break, sleep_start, wake_time);
}

// D-Bus filter for system events
static DBusHandlerResult dbus_filter(DBusConnection *conn, DBusMessage *msg,
                                     void *user_data) {
  MyApplication *self = MY_APPLICATION(user_data);

  if (dbus_message_is_signal(msg, "org.freedesktop.login1.Manager",
                             "PrepareForSleep")) {
    dbus_bool_t sleeping;
    if (dbus_message_get_args(msg, nullptr, DBUS_TYPE_BOOLEAN, &sleeping,
                              DBUS_TYPE_INVALID)) {
      if (sleeping) {
        g_print("System going to sleep\n");
        self->sleep_start_time = g_get_monotonic_time();
        send_system_event(self, "sleep");
      } else {
        g_print("System woke up\n");
        self->wake_time = g_get_monotonic_time();

        if (self->sleep_start_time > 0) {
          gdouble duration =
              (self->wake_time - self->sleep_start_time) / 1000000.0;
          g_print("Sleep duration: %.1f minutes (threshold: %d minutes)\n",
                  duration / 60, self->sleep_threshold_seconds / 60);

          if (duration >= self->sleep_threshold_seconds) {
            g_print("Long sleep detected: %.1f minutes\n", duration / 60);
            show_break_confirmation_dialog(self, self->sleep_start_time,
                                           self->wake_time, duration);
          }
        }

        send_system_event(self, "wake");
        self->sleep_start_time = 0;
      }
    }
  } else if (dbus_message_is_signal(msg, "org.freedesktop.login1.Session",
                                    "Lock")) {
    g_print("Screen locked\n");
    self->sleep_start_time = g_get_monotonic_time();
  } else if (dbus_message_is_signal(msg, "org.freedesktop.login1.Session",
                                    "Unlock")) {
    g_print("Screen unlocked\n");
    self->wake_time = g_get_monotonic_time();

    if (self->sleep_start_time > 0) {
      gdouble duration = (self->wake_time - self->sleep_start_time) / 1000000.0;
      g_print("Screen lock duration: %.1f minutes (threshold: %d minutes)\n",
              duration / 60, self->sleep_threshold_seconds / 60);

      if (duration >= self->sleep_threshold_seconds) {
        g_print("Long screen lock detected: %.1f minutes\n", duration / 60);
        show_break_confirmation_dialog(self, self->sleep_start_time,
                                       self->wake_time, duration);
      }
    }

    self->sleep_start_time = 0;
  }

  return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

static void setup_system_event_monitors(MyApplication *self) {
  DBusError error;
  dbus_error_init(&error);

  self->dbus_conn = dbus_bus_get(DBUS_BUS_SYSTEM, &error);
  if (dbus_error_is_set(&error)) {
    g_warning("Failed to connect to D-Bus: %s", error.message);
    dbus_error_free(&error);
    return;
  }

  // Add filter for system events
  dbus_bus_add_match(self->dbus_conn,
                     "type='signal',interface='org.freedesktop.login1.Manager',"
                     "member='PrepareForSleep'",
                     &error);
  if (dbus_error_is_set(&error)) {
    g_warning("Failed to add D-Bus match: %s", error.message);
    dbus_error_free(&error);
  }

  dbus_bus_add_match(
      self->dbus_conn,
      "type='signal',interface='org.freedesktop.login1.Session',member='Lock'",
      &error);
  dbus_bus_add_match(self->dbus_conn,
                     "type='signal',interface='org.freedesktop.login1.Session',"
                     "member='Unlock'",
                     &error);

  dbus_connection_add_filter(self->dbus_conn, dbus_filter, self, nullptr);
  dbus_connection_setup_with_g_main(self->dbus_conn, nullptr);
}

static gboolean check_midnight(gpointer user_data) {
  MyApplication *self = MY_APPLICATION(user_data);

  GDateTime *now = g_date_time_new_now_local();
  gint hour = g_date_time_get_hour(now);
  gint minute = g_date_time_get_minute(now);

  // Check if it's midnight (00:00)
  if (hour == 0 && minute == 0) {
    g_print("[MIDNIGHT] Midnight detected, notifying Flutter\n");

    gchar *timestamp = g_date_time_format_iso8601(now);
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "event", fl_value_new_string("midnight"));
    fl_value_set_string_take(args, "timestamp", fl_value_new_string(timestamp));

    fl_method_channel_invoke_method(self->method_channel, "onSystemEvent", args,
                                    nullptr, nullptr, nullptr);

    g_free(timestamp);
  }

  g_date_time_unref(now);
  return G_SOURCE_CONTINUE;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication *self, FlView *view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));

  // Setup native components after Flutter is ready
  setup_system_tray(self);
  setup_method_channel(self);
  setup_system_event_monitors(self);

  // Initialize activity tracker
  self->window_tracker = new ActiveWindowTracker(
      [self](const std::string &app_name, const std::string &window_title,
             const std::string &window_class) {
        send_activity_change(self, app_name.c_str(), window_title.c_str(),
                             window_class.c_str());
      });

  // Start midnight monitor (check every minute)
  self->midnight_timer_id = g_timeout_add_seconds(60, check_midnight, self);

  // Notify Flutter that system has booted - ask for confirmation first
  g_timeout_add_seconds(
      1,
      (GSourceFunc) + [](MyApplication *self) -> gboolean {
        // Only show dialog if user is authenticated
        if (!self->is_authenticated) {
          g_print("[BOOT] User not authenticated - skipping auto check-in "
                  "dialog\n");
          return FALSE;
        }

        GtkWidget *dialog = gtk_message_dialog_new(
            GTK_WINDOW(self->window), GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION,
            GTK_BUTTONS_YES_NO, "Auto Check-In");
        gtk_message_dialog_format_secondary_text(
            GTK_MESSAGE_DIALOG(dialog),
            "System start detected. Do you want to check in now?");

        // Ensure dialog is on top
        gtk_window_set_keep_above(GTK_WINDOW(dialog), TRUE);

        gint response = gtk_dialog_run(GTK_DIALOG(dialog));
        gtk_widget_destroy(dialog);

        if (response == GTK_RESPONSE_YES) {
          g_print("[BOOT] User confirmed auto check-in\n");
          send_system_event(self, "boot");
        } else {
          g_print("[BOOT] User cancelled auto check-in\n");
        }
        return FALSE;
      },
      self);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication *application) {
  MyApplication *self = MY_APPLICATION(application);
  self->window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen *screen = gtk_window_get_screen(self->window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar *wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar *header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "time_trak");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(self->window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(self->window, "time_trak");
  }

  gtk_window_set_default_size(self->window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  self->view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(self->view, &background_color);
  gtk_widget_show(GTK_WIDGET(self->view));
  gtk_container_add(GTK_CONTAINER(self->window), GTK_WIDGET(self->view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(self->view, "first-frame",
                           G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(self->view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(self->view));

  gtk_widget_grab_focus(GTK_WIDGET(self->view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication *application,
                                                  gchar ***arguments,
                                                  int *exit_status) {
  MyApplication *self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication *application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication *application) {
  MyApplication *self = MY_APPLICATION(application);

  // Notify Flutter about shutdown
  send_system_event(self, "shutdown");

  // Clean up midnight timer
  if (self->midnight_timer_id > 0) {
    g_source_remove(self->midnight_timer_id);
  }

  // Clean up activity tracker
  if (self->window_tracker) {
    delete self->window_tracker;
    self->window_tracker = nullptr;
  }

  // Clean up D-Bus
  if (self->dbus_conn) {
    dbus_connection_unref(self->dbus_conn);
  }

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject *object) {
  MyApplication *self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->current_status, g_free);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass *klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication *self) {
  self->current_status = g_strdup("Checked Out");
  self->sleep_threshold_seconds = 900; // Default: 15 minutes
  self->is_showing_break_dialog = FALSE;
  self->sleep_start_time = 0;
  self->wake_time = 0;
  self->midnight_timer_id = 0;
  self->dbus_conn = nullptr;
  self->window_tracker = nullptr;
  self->is_tracking_enabled = FALSE;
  self->is_authenticated = FALSE;
}

MyApplication *my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
