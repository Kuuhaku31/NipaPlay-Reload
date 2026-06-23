#include "windows_native_video.h"

#include <flutter/binary_messenger.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iterator>
#include <optional>
#include <string>
#include <variant>

namespace {

constexpr char kChannelName[] = "nipaplay/windows_native_video";
constexpr int64_t kWindowHostedVideoSurfaceId = -1;
constexpr wchar_t kOverlayWindowClassName[] =
    L"NipaPlayWindowsNativeVideoOverlay";

std::optional<int64_t> ToInt64(const flutter::EncodableValue& value) {
  if (const auto* i32 = std::get_if<int32_t>(&value)) {
    return static_cast<int64_t>(*i32);
  }
  if (const auto* i64 = std::get_if<int64_t>(&value)) {
    return *i64;
  }
  if (const auto* d = std::get_if<double>(&value)) {
    return static_cast<int64_t>(*d);
  }
  if (const auto* s = std::get_if<std::string>(&value)) {
    try {
      return std::stoll(*s);
    } catch (...) {
      return std::nullopt;
    }
  }
  return std::nullopt;
}

std::optional<int64_t> ReadInt64(const flutter::EncodableMap& args,
                                 const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return std::nullopt;
  }
  return ToInt64(it->second);
}

double ReadDouble(const flutter::EncodableMap& args,
                  const char* key,
                  double fallback = 0.0) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* d = std::get_if<double>(&it->second)) {
    return *d;
  }
  if (const auto* i32 = std::get_if<int32_t>(&it->second)) {
    return static_cast<double>(*i32);
  }
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) {
    return static_cast<double>(*i64);
  }
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    try {
      return std::stod(*s);
    } catch (...) {
      return fallback;
    }
  }
  return fallback;
}

bool ReadBool(const flutter::EncodableMap& args,
              const char* key,
              bool fallback = false) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* b = std::get_if<bool>(&it->second)) {
    return *b;
  }
  if (const auto* i32 = std::get_if<int32_t>(&it->second)) {
    return *i32 != 0;
  }
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) {
    return *i64 != 0;
  }
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    const std::string value = *s;
    return value == "1" || value == "true" || value == "yes" ||
           value == "on";
  }
  return fallback;
}

int LogicalToPhysical(HWND window, double value) {
  const UINT dpi = ::GetDpiForWindow(window);
  const double scale = dpi > 0 ? static_cast<double>(dpi) / 96.0 : 1.0;
  return static_cast<int>(std::lround(value * scale));
}

bool IsOverlayBelowFlutterEnabled() {
  wchar_t value[8] = {};
  const DWORD length = ::GetEnvironmentVariableW(
      L"NIPAPLAY_WINDOWS_HDR_WINDOW_OVERLAY_BELOW", value,
      static_cast<DWORD>(std::size(value)));
  return length > 0 && value[0] == L'1';
}

LRESULT CALLBACK OverlayWndProc(HWND hwnd,
                                UINT message,
                                WPARAM wparam,
                                LPARAM lparam) {
  switch (message) {
    case WM_NCHITTEST:
      return HTTRANSPARENT;
    case WM_ERASEBKGND:
      return 1;
    default:
      return ::DefWindowProc(hwnd, message, wparam, lparam);
  }
}

void RegisterOverlayWindowClass() {
  static bool registered = false;
  if (registered) {
    return;
  }

  WNDCLASSW window_class = {};
  window_class.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
  window_class.hInstance = ::GetModuleHandle(nullptr);
  window_class.lpszClassName = kOverlayWindowClassName;
  window_class.lpfnWndProc = OverlayWndProc;
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(::GetStockObject(
      BLACK_BRUSH));

  ::RegisterClassW(&window_class);
  registered = true;
}

}  // namespace

WindowsNativeVideoPlugin::WindowsNativeVideoPlugin(
    HWND host_window,
    HWND flutter_view,
    flutter::BinaryMessenger* messenger)
    : host_window_(host_window), flutter_view_(flutter_view) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

WindowsNativeVideoPlugin::~WindowsNativeVideoPlugin() {
  Destroy();
}

void WindowsNativeVideoPlugin::SetFlutterView(HWND flutter_view) {
  flutter_view_ = flutter_view;
}

void WindowsNativeVideoPlugin::Destroy() {
  if (overlay_window_ != nullptr) {
    ::DestroyWindow(overlay_window_);
    overlay_window_ = nullptr;
  }
  overlay_visible_ = false;
  attached_player_handle_ = 0;
}

void WindowsNativeVideoPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args =
      method_call.arguments()
          ? std::get_if<flutter::EncodableMap>(method_call.arguments())
          : nullptr;
  if (!args) {
    result->Error("INVALID_ARGUMENTS", "Arguments are required");
    return;
  }

  const auto view_id = ReadInt64(*args, "viewId");
  if (!view_id.has_value() || view_id.value() != kWindowHostedVideoSurfaceId) {
    result->Error("VIEW_NOT_FOUND",
                  "Only the window-hosted Windows native video surface is "
                  "supported");
    return;
  }

  const auto& method = method_call.method_name();
  if (method == "getViewHandles") {
    if (EnsureOverlayWindow() == nullptr) {
      result->Error("WINDOW_CREATE_FAILED",
                    "Unable to create Windows native video overlay");
      return;
    }
    result->Success(flutter::EncodableValue(BuildHandles()));
    return;
  }

  if (method == "attachPlayer") {
    if (EnsureOverlayWindow() == nullptr) {
      result->Error("WINDOW_CREATE_FAILED",
                    "Unable to create Windows native video overlay");
      return;
    }
    attached_player_handle_ = ReadInt64(*args, "playerHandle").value_or(0);
    result->Success(flutter::EncodableValue(BuildHandles()));
    return;
  }

  if (method == "detachPlayer") {
    HideOverlayWindow();
    attached_player_handle_ = 0;
    result->Success();
    return;
  }

  if (method == "setOverlayFrame") {
    UpdateOverlayFrame(*args);
    result->Success();
    return;
  }

  if (method == "getViewDiagnostics") {
    result->Success(flutter::EncodableValue(BuildDiagnostics()));
    return;
  }

  result->NotImplemented();
}

HWND WindowsNativeVideoPlugin::EnsureOverlayWindow() {
  if (overlay_window_ != nullptr) {
    return overlay_window_;
  }
  if (host_window_ == nullptr) {
    return nullptr;
  }

  RegisterOverlayWindowClass();
  overlay_window_ = ::CreateWindowExW(
      WS_EX_TRANSPARENT | WS_EX_NOACTIVATE, kOverlayWindowClassName,
      L"NipaPlay Native Video", WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN,
      0, 0, 1, 1, host_window_, nullptr, ::GetModuleHandle(nullptr), nullptr);

  if (overlay_window_ != nullptr) {
    ::ShowWindow(overlay_window_, SW_HIDE);
  }
  return overlay_window_;
}

void WindowsNativeVideoPlugin::HideOverlayWindow() {
  if (overlay_window_ == nullptr) {
    return;
  }
  overlay_visible_ = false;
  ::SetWindowPos(overlay_window_, nullptr, 0, 0, 0, 0,
                 SWP_HIDEWINDOW | SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE |
                     SWP_NOZORDER);
}

void WindowsNativeVideoPlugin::UpdateOverlayFrame(
    const flutter::EncodableMap& args) {
  const bool visible = ReadBool(args, "visible", true);
  const double width = ReadDouble(args, "width");
  const double height = ReadDouble(args, "height");
  if (!visible || width <= 0.0 || height <= 0.0) {
    HideOverlayWindow();
    return;
  }

  const HWND overlay = EnsureOverlayWindow();
  if (overlay == nullptr) {
    return;
  }

  const int x = LogicalToPhysical(host_window_, ReadDouble(args, "x"));
  const int y = LogicalToPhysical(host_window_, ReadDouble(args, "y"));
  const int w = std::max(1, LogicalToPhysical(host_window_, width));
  const int h = std::max(1, LogicalToPhysical(host_window_, height));
  const HWND insert_after =
      IsOverlayBelowFlutterEnabled() ? HWND_BOTTOM : HWND_TOP;

  ::SetWindowPos(overlay, insert_after, x, y, w, h,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
  overlay_visible_ = true;
}

flutter::EncodableMap WindowsNativeVideoPlugin::BuildHandles() const {
  flutter::EncodableMap result;
  result[flutter::EncodableValue("viewId")] =
      flutter::EncodableValue(kWindowHostedVideoSurfaceId);
  result[flutter::EncodableValue("viewHandle")] =
      flutter::EncodableValue(static_cast<int64_t>(
          reinterpret_cast<intptr_t>(overlay_window_)));
  result[flutter::EncodableValue("windowHandle")] =
      flutter::EncodableValue(
          static_cast<int64_t>(reinterpret_cast<intptr_t>(host_window_)));
  return result;
}

flutter::EncodableMap WindowsNativeVideoPlugin::BuildDiagnostics() const {
  flutter::EncodableMap result = BuildHandles();
  result[flutter::EncodableValue("flutterViewHandle")] =
      flutter::EncodableValue(
          static_cast<int64_t>(reinterpret_cast<intptr_t>(flutter_view_)));
  result[flutter::EncodableValue("attachedPlayerHandle")] =
      flutter::EncodableValue(attached_player_handle_);
  result[flutter::EncodableValue("visible")] =
      flutter::EncodableValue(overlay_visible_);

  RECT rect = {};
  if (overlay_window_ != nullptr) {
    ::GetWindowRect(overlay_window_, &rect);
  }
  flutter::EncodableMap frame;
  frame[flutter::EncodableValue("left")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.left));
  frame[flutter::EncodableValue("top")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.top));
  frame[flutter::EncodableValue("right")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.right));
  frame[flutter::EncodableValue("bottom")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.bottom));
  result[flutter::EncodableValue("windowRect")] =
      flutter::EncodableValue(frame);
  return result;
}
